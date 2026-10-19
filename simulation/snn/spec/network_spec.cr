require "spec"
require "../src/network"
require "../src/type"
require "../src/node/*"
require "../src/constant"
require "../src/worker"
require "../src/event"
require "./support/worker_schedule_probe"
require "./support/network_probe"

alias LIFNetwork = Network(LIFNode, Tuple(UInt8, Float64), Tuple(UInt8, Bool))
alias AccumulatorNetwork = Network(AccumulatorNode, UInt64, UInt64)

describe Network do
  describe "#initialize and construction helpers" do
    it "creates the correct number of nodes with proper layer indices" do
      layer_sizes = [10_u32, 3_u32]
      network = AccumulatorNetwork.new(layer_sizes, MAX_WORKERS)
      workers = network.workers
      workers.size.should eq(8)
      worker0 = workers[0]
      worker1 = workers[1]
      network.worker_id_for_node(0).should eq(0)
      network.worker_id_for_node(1).should eq(1)
      network.worker_id_for_node(2).should eq(2)
      network.worker_id_for_node(3).should eq(3)
      network.worker_id_for_node(9).should eq(1)
      worker0.nodes_in_layer(0).size.should eq(2)
      worker0.nodes_in_layer(1).size.should eq(1)
      worker1.nodes_in_layer(0).size.should eq(2)
      worker1.nodes_in_layer(1).size.should eq(1)
    end

    it "creates the expected number of workers" do
      network = AccumulatorNetwork.new([2_u32, 2_u32], MAX_WORKERS)
      network.workers.size.should eq(MAX_WORKERS)

      network.workers.each_with_index do |worker, i|
        worker.worker_id.should eq(i)
      end
    end
  end

  describe "#layer_idx" do
    worker_count = 8_u32
    network = AccumulatorNetwork.new([100_u32], worker_count)

    it "returns 0 for nodes in layer 0" do
      network.layer_idx(0u32).should eq(0u32)
      network.layer_idx(100u32).should eq(0u32)
      network.layer_idx(4095u32).should eq(0u32)
    end

    it "returns 1 for nodes in layer 1" do
      network.layer_idx(4096u32).should eq(1u32)
      network.layer_idx(5000u32).should eq(1u32)
      network.layer_idx(8191u32).should eq(1u32)
    end

    it "returns correct layer for higher layers" do
      network.layer_idx(8192u32).should eq(2u32)   # 2 * 4096
      network.layer_idx(12287u32).should eq(2u32)
      network.layer_idx(12288u32).should eq(3u32)  # 3 * 4096
    end
  end

  describe "#node_idx_within_layer" do
    worker_count = 8_u32
    network = AccumulatorNetwork.new([100_u32], worker_count)

    it "returns offset within layer 0" do
      network.node_idx_within_layer(0u32).should eq(0u32)
      network.node_idx_within_layer(100u32).should eq(100u32)
      network.node_idx_within_layer(4095u32).should eq(4095u32)
    end

    it "returns offset within layer 1" do
      network.node_idx_within_layer(4096u32).should eq(0u32)
      network.node_idx_within_layer(5000u32).should eq(904u32)   # 5000 - 4096
      network.node_idx_within_layer(8191u32).should eq(4095u32)
    end

    it "returns offset within higher layers" do
      network.node_idx_within_layer(8192u32).should eq(0u32)
      network.node_idx_within_layer(12287u32).should eq(4095u32)
      network.node_idx_within_layer(12288u32).should eq(0u32)
    end
  end

  describe "#worker_id_for_node" do
    worker_count = MAX_WORKERS
    network = AccumulatorNetwork.new([100_u32], worker_count)
    it "maps nodes round-robin across MAX_WORKERS workers" do
      63.times do |i|
        node_id = i.to_u32
        expected_worker = (i % MAX_WORKERS).to_u32
        network.worker_id_for_node(node_id).should eq(expected_worker)
      end
    end

    it "works for large node ids" do
      network.worker_id_for_node(1000u32).should eq((1000 % 8).to_u32)
      network.worker_id_for_node(12345u32).should eq((12345 % 8).to_u32)
      network.worker_id_for_node(0xFFFFFFFFu32).should eq((0xFFFFFFFFu32 % 8).to_u32)
    end
  end

  describe "#local_node_idx" do
    worker_count = 8_u32
    network = AccumulatorNetwork.new([100_u32], worker_count)
    it "gives index within worker's array for small ids" do
      # worker 0 owns 0,8,16,... -> local indices 0,1,2,...
      network.worker_local_node_idx(0u32).should eq(0u32)
      network.worker_local_node_idx(8u32).should eq(1u32)
      network.worker_local_node_idx(16u32).should eq(2u32)

      # worker 1 owns 1,9,17,... -> local indices 0,1,2,...
      network.worker_local_node_idx(1u32).should eq(0u32)
      network.worker_local_node_idx(9u32).should eq(1u32)
      network.worker_local_node_idx(17u32).should eq(2u32)
    end

    it "is monotonic within each worker's residue class" do
      100.times do |i|
        node_id = i.to_u32
        expected_local = (node_id >> WORKERS_SHIFT)
        network.worker_local_node_idx(node_id).should eq(expected_local)
      end
    end
  end

  describe "#node_id(layer, idx_in_layer)" do
    worker_count = 8_u32
    network = AccumulatorNetwork.new([100_u32], worker_count)

    it "reconstructs global id for layer 0" do
      network.node_id(0u32, 0u32).should eq(0u32)
      network.node_id(0u32, 100u32).should eq(100u32)
      network.node_id(0u32, 4095u32).should eq(4095u32)
    end

    it "reconstructs global id for layer 1" do
      network.node_id(1u32, 0u32).should eq(4096u32)
      network.node_id(1u32, 500u32).should eq(4596u32)     # 4096 + 500
      network.node_id(1u32, 4095u32).should eq(8191u32)    # 4096 + 4095
    end

    it "reconstructs global id for higher layers" do
      network.node_id(2u32, 0u32).should eq(8192u32)       # 2 * 4096
      network.node_id(2u32, 100u32).should eq(8292u32)     # 8192 + 100
      network.node_id(3u32, 4095u32).should eq(16383u32)   # 3 * 4096 + 4095
    end

    it "is inverse of layer_idx and node_idx_within_layer" do
      10_000.times do |i|
        layer = (i // 4096).to_u32
        idx   = (i % 4096).to_u32
        node_id = network.node_id(layer, idx)
        network.layer_idx(node_id).should eq(layer)
        network.node_idx_within_layer(node_id).should eq(idx)
      end
    end
  end

  describe "Worker layer-contiguous layout" do
    worker_count = 8_u32
    network = AccumulatorNetwork.new([100_u32], worker_count)

    it "adds nodes and keeps layer-contiguous layout" do
      num_layers = 4_u32
      worker = Worker.new(0u32, network, num_layers)

      # Add nodes in layer order: layer 0, then 1, then 2, etc.
      # Layer 0: global ids 0..4095
      # Layer 1: 4096..8191
      # Layer 2: 8192..12287
      [0u32, 100u32, 4095u32,      # layer 0
       4096u32, 5000u32,           # layer 1
       8192u32, 10000u32, 12287u32 # layer 2
      ].each { |id| worker.add_node(id) }

      # Check counts
      worker.nodes.size.should eq(8)

      layer0 = worker.nodes_in_layer(0u32)
      layer1 = worker.nodes_in_layer(1u32)
      layer2 = worker.nodes_in_layer(2u32)
      layer3 = worker.nodes_in_layer(3u32)

      layer0.size.should eq(3)
      layer1.size.should eq(2)
      layer2.size.should eq(3)
      layer3.size.should eq(0)

      # Check that nodes_in_layer returns the correct node_ids in order
      layer0.map(&.node_id).should eq([0u32, 100u32, 4095u32])
      layer1.map(&.node_id).should eq([4096u32, 5000u32])
      layer2.map(&.node_id).should eq([8192u32, 10000u32, 12287u32])
    end

    it "returns empty array for layers with no nodes" do
      worker = Worker.new(1u32, network, 3_u32)
      worker.add_node(0u32)      # layer 0
      worker.add_node(4096u32)   # layer 1

      worker.nodes_in_layer(2u32).should eq([] of Node(ActiveNode, ActiveReturn))
    end

    it "maintains contiguity when multiple layers are present" do
      worker = Worker.new(2u32, network, 3_u32)

      # Add in layer order: respect the contract to add per layer in order
      [0u32, 1u32, 4096u32, 4097u32, 8192u32].each { |id| worker.add_node(id) }

      # Layers:
      # 0: 0, 1
      # 1: 4096, 4097
      # 2: 8192
      worker.nodes_in_layer(0u32).map(&.node_id).should eq([0u32, 1u32])
      worker.nodes_in_layer(1u32).map(&.node_id).should eq([4096u32, 4097u32])
      worker.nodes_in_layer(2u32).map(&.node_id).should eq([8192u32])
    end
  end

  describe "#input" do
    it "routes events to correct worker based on node_id" do
      network = AccumulatorNetwork.new([10_u32], MAX_WORKERS)

      # Node 0 should go to worker 0 (0 % 8 = 0)
      network.input(0_u32, 100_u64, 0_u64)
      # Node 1 should go to worker 1 (1 % 8 = 1)
      network.input(1_u32, 100_u64, 0_u64)
      # Node 8 should go to worker 0 (8 % 8 = 0)
      network.input(8_u32, 100_u64, 0_u64)

      worker_for_node_0 = network.worker_for_node(0)
      worker_for_node_1 = network.worker_for_node(1)

      worker_for_node_0.scheduled_events.size.should eq 2
      worker_for_node_1.scheduled_events.size.should eq 1
    end

    it "schedules an event on the correct worker" do
      network = AccumulatorNetwork.new([3_u32], MAX_WORKERS)

      node_id = 1_u32
      process_at = 10_u64
      expected_worker_id = network.worker_id_for_node(node_id)
      workers = network.workers_for_spec

      network.input(node_id, process_at, 0_u64)

      workers.each do |worker|
        if worker.worker_id == expected_worker_id
          worker.scheduled_events.size.should eq 1
          event = worker.scheduled_events.first
          event.target_local_node_idx.should eq 0
          event.scheduled_time.should eq(process_at)
        else
          worker.scheduled_events.should be_empty
        end
      end
    end
  end

  describe "#run_worker_loop_iteration" do
    it "processes events strictly within the safe horizon and synchronises with SyncManager" do
      # Setup real Network instance with known layer delay and loader time.
      max_drift = 4_u64
      network = AccumulatorNetwork.new([1_u32], worker_count: MAX_WORKERS, max_drift: max_drift)
      worker0 = network.workers[0]
      worker1 = network.workers[1]
      sync_mgr = network.sync_mgr
      network.reset(10_u64, 999_999_u64)
      sync_mgr.set_worker_next_tick(1, 20)
      sync_mgr.set_worker_next_tick(2, 20)
      sync_mgr.set_worker_next_tick(3, 20)
      sync_mgr.set_worker_next_tick(4, 20)
      sync_mgr.set_worker_next_tick(5, 20)
      sync_mgr.set_worker_next_tick(6, 20)
      sync_mgr.set_worker_next_tick(7, 20)
      sync_mgr.horizon_next_tick(0).should eq 20 + max_drift

      # Schedule real events on worker0's actual hierarchical wheel.
      target_node_id = 0_u32
      worker0.schedule(target_node_id, 21_u64, 1_u64)
      worker0.schedule(target_node_id, 23_u64, 1_u64)
      # Event at t=25 is beyond the safe horizon (24).
      worker0.schedule(target_node_id, 25_u64, 1_u64)

      # Execute a single iteration synchronously on the calling thread.
      result = worker0.iterate
      result.should eq :iterated

      # Assertions on real objects.
      # Clock advanced strictly to the safe horizon boundary (4).
      worker0.next_tick.should eq 24_u64

      # Real SyncManager reflects worker0's reported time.
      sync_mgr.worker_next_tick(0).should eq 24_u64

      # Exactly 2 events (t=1 and t=3) were processed; event at t=5 was NOT touched.
      target_node = worker0.nodes[target_node_id]
      target_node.processed_count.should eq 2

      # Verify that the event at t=5 is still safely queued in the wheel:
      # Catch worker1 up to t=22, which moves horizon_next_tick to min(22 + 4, 24) = 26.
      network.record_progress(worker1.worker_id, 22_u64)
      network.record_progress(2, 22_u64)
      network.record_progress(3, 22_u64)
      network.record_progress(4, 22_u64)
      network.record_progress(5, 22_u64)
      network.record_progress(6, 22_u64)
      network.record_progress(7, 22_u64)
      network.horizon_next_tick(worker0.worker_id).should eq 26_u64

      # Run the next iteration for worker0: now the horizon includes t=25
      worker0.iterate

      worker0.next_tick.should eq 26_u64
      target_node.processed_count.should eq 3
    end

    it "processes an event and dispatches via router" do
      # Create a small network with a single worker so we control timing easily.
      network = AccumulatorNetwork.new(layer_sizes: [1_u32, 1_u32], worker_count: MAX_WORKERS, layer_latency: 100_u64, max_drift: 5000_u64)
      network.reset(10_u64, 150_u64)
      input_node_id = network.node_id(0,0)
      input_node_id.should eq 0
      output_node_id = network.node_id(1,0)
      output_node_id.should eq 4096
      worker0 = network.worker_for_node(input_node_id)
      worker0.worker_id.should eq 0
      worker1 = network.worker_for_node(output_node_id)
      worker1.worker_id.should eq 0
      input_node_local_idx = network.worker_local_node_idx(input_node_id)
      input_node_local_idx.should eq 0
      input_node = worker0.nodes[input_node_local_idx]
      input_node.node_id.should eq 0
      output_node_local_idx = network.worker_local_node_idx(output_node_id)
      output_node_local_idx.should eq 1
      output_node = worker1.nodes[output_node_local_idx]
      output_node.node_id.should eq 4096
      input_node.processed_count.should eq 0
      input_node.accumulation.should eq 0
      output_node.processed_count.should eq 0
      output_node.accumulation.should eq 0

      # Ensure the worker starts at a known time.
      # Clock is initialized with next_tick = 0 in Worker.new.
      worker0.next_tick.should eq 10_u64
      network.horizon_next_tick(0).should eq 110_u64

      # Enqueue an input event for node 0 to be processed at time 5.
      process_at = 90_u64
      network.input(input_node.node_id, process_at, 0_u64)
      # The event should now be scheduled in the clock at time 100.

      # Step time forward to so that the next tick processes the specified time (half open).
      result = worker0.iterate
      result.should eq :iterated
      # Note worker can never advance faster than latency, so it has a chance to process
      # events it created in the previous layer.
      worker0.next_tick.should eq 110_u64

      input_node.processed_count.should eq 1
      input_node.accumulation.should eq 1
      output_node.processed_count.should eq 0
      output_node.accumulation.should eq 0

      result = worker0.iterate
      result.should eq :iterated
      worker0.next_tick.should eq 210_u64

      output_node.processed_count.should eq 1
      output_node.accumulation.should eq 1

      result = worker0.iterate
      result.should eq :iterated
      worker0.next_tick.should eq 250_u64
    end
  end

  describe "#reset" do
    it "resets worker clocks and sync state" do
      network = AccumulatorNetwork.new([1_u32], 1_u32)

      # Advance time and do some work so clocks are non‑zero.
      worker0 = network.workers[0]

      # Simulate some progression: enqueue and drain to move clocks.
      network.input(0_u32, 10_u64, 0_u64)
      network.input(0_u32, 20_u64, 0_u64)

      # Manually advance their clocks a bit.
      worker0.iterate

      # Now reset the network at a new base time.
      first_event_time = 100_u64
      last_event_time = 200_u64
      network.reset(first_event_time, last_event_time)

      network.workers.each(&.next_tick.should eq(first_event_time))
      network.sync_mgr.all_workers_at_time?(first_event_time).should be_true
    end
  end

  describe "#propagate" do
    context "when ActiveReturn is Bool and ActivePayload is Float64" do
      it "returns early and schedules nothing if state is false" do
        network = LIFNetwork.new([1_u32], 1_u32)
        worker = network.workers[0]
        node = LIFNode.new(1_u32)
        route = TargetRoute.new(0, 0)
        node.add_target_route(route)
        network.propagate(node, 10_u64, {1_u8, false})
        worker.scheduled_events.should be_empty
      end

      it "calculates target time and schedules payload using route weight when state is true" do
        network = LIFNetwork.new([1_u32], 1_u32, layer_latency: 5)
        worker = network.workers[0]
        node = LIFNode.new(1_u32)

        route1 = TargetRoute.new(target_worker_id: 0, target_local_node_idx: 2) #TODO weight: 1.5,
        route2 = TargetRoute.new(target_worker_id: 0, target_local_node_idx: 3) #TODO weight: 2.5,
        node.add_target_route(route1)
        node.add_target_route(route2)
        network.propagate(node, 10_u64, {1_u8, true})

        worker.scheduled_events.size.should eq(2)
        worker.scheduled_events[0].target_local_node_idx.should eq(2)
        worker.scheduled_events[0].scheduled_time.should eq(15_u64) # 10 + 5
        worker.scheduled_events[0].payload.should eq({1_u8, 0.0})

        worker.scheduled_events[1].target_local_node_idx.should eq(3)
        worker.scheduled_events[1].scheduled_time.should eq(15_u64)
        worker.scheduled_events[1].payload.should eq({1, 0.0}) # 2.5 route weight
      end
    end

    context "when ActiveReturn is Int32 and ActivePayload is Int32" do
      it "schedules state as the payload directly without checking truthiness" do
        network = AccumulatorNetwork.new([1_u32], 1_u32, layer_latency: 10)
        worker = network.workers[0]
        node = AccumulatorNode.new(1_u32, 0_u64)
        route = TargetRoute.new(target_worker_id: 0, target_local_node_idx: 1) # weight: 99.9,
        node.add_target_route(route)

        network.propagate(node, 5_u64, 42)

        worker.scheduled_events.size.should eq(1)
        worker.scheduled_events[0].target_local_node_idx.should eq(1)
        worker.scheduled_events[0].scheduled_time.should eq(15_u64) # 5 + 10
        worker.scheduled_events[0].payload.should eq(42)   # passed state, NOT route weight
      end
    end
  end

  describe "sample-end marker integration" do
    it "exposes sync_mgr for sample end time management" do
      network = AccumulatorNetwork.new([1_u32], 1_u32)
      network.sync_mgr.should_not be_nil
      network.sync_mgr.is_a?(SyncManager).should be_true
    end

    it "allows setting sample end time via sync_mgr" do
      network = AccumulatorNetwork.new([1_u32], 1_u32)
      sample_start = 1000_u64
      sample_end = 1000_u64

      network.sync_mgr.reset(sample_start, sample_end)
      # This tests that the method exists and is callable
      # The actual behavior is tested in SyncManager specs
    end

    it "resets all state including sample_end markers" do
      network = AccumulatorNetwork.new([1_u32], MAX_WORKERS)
      t0 = 500_u64
      t_end = 1000_u64

      # Set up a sample
      network.sync_mgr.reset(t0, t_end)

      # Advance workers past sample end
      network.workers.each { |worker| network.sync_mgr.record_progress(worker.worker_id, 1050_u64) }
      network.sync_mgr.record_progress(0, 1050_u64)
      network.sync_mgr.record_progress(1, 1050_u64)

      # Verify workers are marked done
      network.sync_mgr.all_workers_at_time?(1050).should be_true

      # Reset for new sample
      network.reset(t0, t_end)

      # All workers should be reset
      network.sync_mgr.all_workers_at_time?(t0).should be_true
    end
  end

  describe "sample processing workflow" do
    it "supports complete sample lifecycle" do
      # Simulate the pattern from main.cr training loop
      network = AccumulatorNetwork.new([10_u32, 5_u32], MAX_WORKERS)

      # Sample 1: events from t=0 to t=100
      t0 = 0_u64
      sample1_end = 100_u64

      network.reset(t0, sample1_end)

      # Feed events
      network.input(0_u32, 10_u64, 0_u64)
      network.input(1_u32, 20_u64, 0_u64)
      network.input(2_u32, 50_u64, 0_u64)
      network.input(3_u32, 100_u64, 0_u64)

      # Manually advance workers to simulate processing
      network.workers.each(&.iterate)

      # All workers should be done
      network.sync_mgr.all_workers_at_time?(sample1_end).should be_true

      # Sample 2: reset and process new sample
      t0_sample2 = 200_u64
      sample2_end = 300_u64
      network.reset(t0_sample2, sample2_end)

      # Workers should be reset
      # TODO network.sync_mgr.all_workers_finished_sample?.should be_false

      # Feed sample 2 events
      network.input(0_u32, 210_u64, 0_u64)
      network.input(1_u32, 250_u64, 0_u64)
      network.input(2_u32, 300_u64, 0_u64)

      # Advance workers
      network.workers.each(&.iterate)

      # TODO network.sync_mgr.all_workers_finished_sample?.should be_true
      network.sync_mgr.all_workers_at_time?(sample2_end).should be_true

    end
  end

  describe "Network routing and address translation" do
    it "correctly computes global node IDs and within-layer indices for 4096-node stride" do
      net = AccumulatorNetwork.new([2312_u32, 10_u32, 200_u32], 8_u32)

      # Layer 0 boundary checks
      node_0 = net.node_id(0_u32, 0_u32)
      node_0.should eq(0_u32)
      net.layer_idx(node_0).should eq(0_u32)
      net.node_idx_within_layer(node_0).should eq(0_u32)
      net.worker_id_for_node(node_0).should eq(0_u32)

      node_2311 = net.node_id(0_u32, 2311_u32)
      node_2311.should eq(2311_u32)
      net.layer_idx(node_2311).should eq(0_u32)
      net.node_idx_within_layer(node_2311).should eq(2311_u32)
      net.worker_id_for_node(node_2311).should eq(2311_u32 & 7_u32)

      # Layer 1 checks
      node_l1_0 = net.node_id(1_u32, 0_u32)
      node_l1_0.should eq(4096_u32)
      net.layer_idx(node_l1_0).should eq(1_u32)
      net.node_idx_within_layer(node_l1_0).should eq(0_u32)
      net.worker_id_for_node(node_l1_0).should eq(0_u32)

      # Layer 2 checks
      node_l2_0 = net.node_id(2_u32, 0_u32)
      node_l2_0.should eq(8192_u32)
      net.layer_idx(node_l2_0).should eq(2_u32)
      net.node_idx_within_layer(node_l2_0).should eq(0_u32)
    end

    it "distributes uneven layer sizes across all 8 workers with correct local indices" do
      # Layer sizes: [1, 1]
      net1 = AccumulatorNetwork.new([1_u32, 1_u32], 8_u32)
      id0 = net1.node_id(0_u32, 0_u32) # 0
      id1 = net1.node_id(1_u32, 0_u32) # 4096

      net1.worker_id_for_node(id0).should eq(0_u32)
      net1.worker_id_for_node(id1).should eq(0_u32)
      net1.worker_local_node_idx(id0).should eq(0_u32)
      net1.worker_local_node_idx(id1).should eq(1_u32)

      worker0 = net1.workers[0]
      worker0.nodes.size.should eq(2)
      worker0.nodes[0].node_id.should eq(id0)
      worker0.nodes[1].node_id.should eq(id1)

      (1..7).each do |worker|
        net1.workers[worker].nodes.size.should eq(0)
      end
    end

    it "handles uneven distribution for [2312, 10, 200]" do
      layer_sizes = [2312_u32, 10_u32, 200_u32]
      net = AccumulatorNetwork.new(layer_sizes, 8_u32)

      # 2312 / 8 = 289 evenly
      # 10 / 8 = 1 remainder 2 (workers 0 and 1 receive 2, others 1)
      # 200 / 8 = 25 evenly
      # Worker 0 & 1: 289 + 2 + 25 = 316
      # Worker 2..7:  289 + 1 + 25 = 315
      net.workers[0].nodes.size.should eq(316)
      net.workers[1].nodes.size.should eq(316)
      (2..7).each do |worker|
        net.workers[worker].nodes.size.should eq(315)
      end

      # Verify that worker local indices map 1-to-1 to worker.nodes positions
      layer_sizes.each_with_index(0_u32) do |size, l_idx|
        size.times do |n_idx|
          g_id = net.node_id(l_idx, n_idx)
          w_id = net.worker_id_for_node(g_id)
          local_idx = net.worker_local_node_idx(g_id)

          target_node = net.workers[w_id].nodes[local_idx]
          target_node.node_id.should eq(g_id)
        end
      end
    end

    it "precomputes correct routes for every source node" do
      net = AccumulatorNetwork.new([2312_u32, 10_u32, 200_u32], 8_u32)

      # Check layer 0 nodes: each must have 10 routes connecting to all nodes of layer 1
      src_node_0 = net.node_by_id(net.node_id(0_u32, 0_u32))
      src_node_0.target_routes.size.should eq(10)

      10_u32.times do |target_n_idx|
        expected_target_id = net.node_id(1_u32, target_n_idx)
        expected_worker_id = net.worker_id_for_node(expected_target_id)
        expected_local_idx = net.worker_local_node_idx(expected_target_id)

        route = src_node_0.target_routes[target_n_idx]
        route.target_worker_id.should eq(expected_worker_id)
        route.target_local_node_idx.should eq(expected_local_idx)

        # Target node in worker array must match
        net.workers[route.target_worker_id].nodes[route.target_local_node_idx].node_id.should eq(expected_target_id)
      end

      # Check layer 1 nodes: each must have 200 routes connecting to layer 2
      src_node_l1 = net.node_by_id(net.node_id(1_u32, 5_u32))
      src_node_l1.target_routes.size.should eq(200)

      200_u32.times do |target_n_idx|
        expected_target_id = net.node_id(2_u32, target_n_idx)
        expected_worker_id = net.worker_id_for_node(expected_target_id)
        expected_local_idx = net.worker_local_node_idx(expected_target_id)

        route = src_node_l1.target_routes[target_n_idx]
        route.target_worker_id.should eq(expected_worker_id)
        route.target_local_node_idx.should eq(expected_local_idx)
      end

      # Check layer 2 nodes (last layer): 0 routes
      src_node_l2 = net.node_by_id(net.node_id(2_u32, 0_u32))
      src_node_l2.target_routes.size.should eq(0)
    end

    it "delivers events and propagates across layers without per-event translation in hot path" do
      net = AccumulatorNetwork.new([2_u32, 3_u32, 2_u32], 8_u32, layer_latency: 10_u64, max_drift: 5_u64)
      net.reset(0_u64, 100_u64)

      # Send external input to node (0, 0)
      in_node_id = net.node_id(0_u32, 0_u32)
      net.input(in_node_id, 10_u64, 0_u64)

      # Run the network to convergence
      net.run

      # Node (0, 0) should have processed 1 event
      net.node_by_id(in_node_id).processed_count.should eq(1_u64)
      # Node (0, 1) had no input
      net.node_by_id(net.node_id(0_u32, 1_u32)).processed_count.should eq(0_u64)

      # Layer 1 has 3 nodes; each should have received propagation from node (0, 0)
      3_u32.times do |i|
        l1_node = net.node_by_id(net.node_id(1_u32, i))
        l1_node.processed_count.should eq(1_u64)
      end

      # Layer 2 has 2 nodes; each should have received propagation from all 3 nodes in layer 1
      2_u32.times do |i|
        l2_node = net.node_by_id(net.node_id(2_u32, i))
        l2_node.processed_count.should eq(3_u64)
      end
    end

    it "propagates labels unchanged across layers" do
      net = LIFNetwork.new([1_u32, 1_u32], 8_u32, layer_latency: 10_u64, max_drift: 5_u64)
      net.reset(0_u64, 1000_u64)

      # Send external input to node (0, 0) with event weight 1.0 label 1
      in_node_id = net.node_id(0_u32, 0_u32)
      net.input(in_node_id, 1_u64, {1_u8, 2.0})

      # Run the network to convergence
      # net.run
      net.node_by_id(in_node_id).potential.should eq 0.0
      net.workers.each(&.iterate)
      # Node (0, 0) should have processed 1 event
      net.node_by_id(in_node_id).potential.should eq -1.0

      net.workers[0].scheduled_events[1].target_local_node_idx.should eq(1_u32)
      net.workers[0].scheduled_events[1].payload[0].should eq(1_u8)
    end
  end
end
