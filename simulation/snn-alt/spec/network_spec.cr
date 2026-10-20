require "spec"
require "../src/constant"
require "../src/network"
require "../src/worker"
require "./support/worker_schedule_probe"
require "./support/network_probe"

alias LIFNetwork = Network(LIFNode, Tuple(UInt8, Float64), Tuple(UInt8, Bool))
alias AccumulatorNetwork = Network(AccumulatorNode, UInt64, UInt64)

describe Network do
  describe "initialisation" do
    it "rejects networks with fewer than two layers" do
      expect_raises(ArgumentError) do
        AccumulatorNetwork.new([4_u16], 2_u8)
      end
    end

    it "rejects zero workers" do
      expect_raises(ArgumentError) do
        AccumulatorNetwork.new([4_u16, 3_u16], 0_u8)
      end
    end

    it "rejects more than the maximum worker count" do
      expect_raises(ArgumentError) do
        AccumulatorNetwork.new([4_u16, 3_u16], MAX_WORKERS + 1_u8)
      end
    end

    it "rejects layers larger than the maximum node count" do
      invalid_layer_size = (MAX_NODES_PER_LAYER + 1_u32).to_u16!

      expect_raises(ArgumentError) do
        AccumulatorNetwork.new(
          [invalid_layer_size, 3_u16],
          2_u8
        )
      end
    end
  end

  describe "with layer sizes [4, 3, 2] and 8 workers" do
    layer_sizes = [4_u16, 3_u16, 2_u16]
    worker_count = 8_u8

    network = AccumulatorNetwork.new(layer_sizes, worker_count, 0.0)

    it "records the requested layer sizes" do
      network.layer_sizes.to_a.should eq(layer_sizes)
    end

    it "computes contiguous layer offsets" do
      network.layer_offsets.to_a.should eq([0_u32, 4_u32, 7_u32, 9_u32])
    end

    it "computes the total node count" do
      network.total_node_count.should eq(9_u32)
    end

    it "allocates nodes round-robin within each layer" do
      expected_worker_ids = [
        0_u8, 1_u8, 2_u8, 3_u8,
        0_u8, 1_u8, 2_u8,
        0_u8, 1_u8
      ]

      network.node_allocations.to_a
        .map(&.worker_id)
        .should eq(expected_worker_ids)
    end

    it "assigns dense worker-local node indices across layers" do
      network.node_allocations[0].worker_local_node_index.should eq(0_u16)
      network.node_allocations[4].worker_local_node_index.should eq(1_u16)
      network.node_allocations[7].worker_local_node_index.should eq(2_u16)

      network.node_allocations[1].worker_local_node_index.should eq(0_u16)
      network.node_allocations[5].worker_local_node_index.should eq(1_u16)
      network.node_allocations[8].worker_local_node_index.should eq(2_u16)

      network.node_allocations[2].worker_local_node_index.should eq(0_u16)
      network.node_allocations[6].worker_local_node_index.should eq(1_u16)

      network.node_allocations[3].worker_local_node_index.should eq(0_u16)
    end

    it "creates one worker per requested worker" do
      network.workers.size.should eq(worker_count)
    end

    it "gives workers unique sequential IDs" do
      network.workers.to_a
        .map(&.worker_id)
        .should eq([0_u8, 1_u8, 2_u8, 3_u8, 4_u8, 5_u8, 6_u8, 7_u8])
    end

    it "counts worker-owned nodes across all layers" do
      expected_node_counts = [3_u32, 3_u32, 2_u32, 1_u32, 0_u32, 0_u32, 0_u32, 0_u32]

      network.workers.to_a
        .map(&.node_count)
        .should eq(expected_node_counts)
    end

    it "allocates the correct number of incoming weights per worker" do
      # Layer 0 -> layer 1 creates 4 incoming edges per target node.
      # Layer 1 -> layer 2 creates 3 incoming edges per target node.
      #
      # Worker 0 owns layer 1 node 0 and layer 2 node 0:
      #   4 + 3 = 7 incoming weights.
      #
      # Worker 1 owns layer 1 node 1 and layer 2 node 1:
      #   4 + 3 = 7 incoming weights.
      #
      # Worker 2 owns layer 1 node 2:
      #   4 incoming weights.
      expected_weight_counts = [7_u32, 7_u32, 4_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32]

      network.workers.to_a
        .map(&.weight_count)
        .should eq(expected_weight_counts)
    end

    it "creates monotonically increasing worker weight offsets" do
      offsets = network.worker_weight_offsets.to_a

      offsets.size.should eq(worker_count + 1)
      offsets[0].should eq(0_u32)

      worker_count.times do |worker_index|
        offsets[worker_index + 1].should be >= offsets[worker_index]
      end
    end

    it "creates the expected total number of routes" do
      expected_route_count = 4_u32 * 3_u32 + 3_u32 * 2_u32

      network.forward_routes.size.should eq(expected_route_count)
      network.backward_routes.size.should eq(expected_route_count)
    end
  end

  describe "forward routes" do
    layer_sizes = [4_u16, 3_u16, 2_u16]
    network = AccumulatorNetwork.new(layer_sizes, 8_u8, 0.0)

    it "gives the first layer-zero node routes to every layer-one node" do
      source_global_index = 0_u32
      route_range = network.forward_route_range(source_global_index)

      route_range.size.should eq(3_u32)

      target_keys = network.forward_routes[route_range].to_a.map do |route|
        route.target_key
      end

      target_keys.should eq([
        NodeKey.new(0_u8, 1_u16),
        NodeKey.new(1_u8, 1_u16),
        NodeKey.new(2_u8, 1_u16)
      ])
    end

    it "gives layer-one nodes routes to every layer-two node" do
      source_global_index = 4_u32
      route_range = network.forward_route_range(source_global_index)

      route_range.size.should eq(2_u32)

      target_keys = network.forward_routes[route_range].to_a.map do |route|
        route.target_key
      end

      target_keys.should eq([
        NodeKey.new(0_u8, 2_u16),
        NodeKey.new(1_u8, 2_u16)
      ])
    end

    it "stores contiguous forward-route offsets" do
      first_layer_node_count = network.layer_sizes[0].to_u32

      first_layer_node_count.times do |layer_local_node_index|
        global_node_index = network.global_node_index(
          0_u32,
          layer_local_node_index.to_u16!
        )

        route_range = network.forward_route_range(global_node_index)

        route_range.size.should eq(3_u32)
      end
    end
  end

  describe "backward routes" do
    layer_sizes = [4_u16, 3_u16, 2_u16]
    network = AccumulatorNetwork.new(layer_sizes, 8_u8, 0.0)

    it "gives the first layer-one node routes from every layer-zero node" do
      target_global_index = 4_u32
      route_range = network.backward_route_range(target_global_index)

      route_range.size.should eq(4_u32)

      source_keys = network.backward_routes[route_range].to_a.map do |route|
        route.source_key
      end

      source_keys.should eq([
        NodeKey.new(0_u8, 0_u16),
        NodeKey.new(1_u8, 0_u16),
        NodeKey.new(2_u8, 0_u16),
        NodeKey.new(3_u8, 0_u16)
      ])
    end

    it "gives each layer-two node routes from every layer-one node" do
      target_global_index = 7_u32
      route_range = network.backward_route_range(target_global_index)

      route_range.size.should eq(3_u32)

      source_keys = network.backward_routes[route_range].to_a.map do |route|
        route.source_key
      end

      source_keys.should eq([
        NodeKey.new(0_u8, 1_u16),
        NodeKey.new(1_u8, 1_u16),
        NodeKey.new(2_u8, 1_u16)
      ])
    end

    it "assigns worker-local weight indices within each worker's weight range" do
      network.workers.each do |worker|
        worker_start = network.worker_weight_offsets[worker.worker_id]
        worker_end = network.worker_weight_offsets[worker.worker_id + 1]

        worker.node_count.times do |worker_local_node_index|
          global_node_index = find_global_node_index(
            network,
            worker.worker_id,
            worker_local_node_index.to_u16!
          )

          next unless global_node_index

          route_range = network.backward_route_range(global_node_index)

          route_range.each do |route_index|
            route = network.backward_routes[route_index]

            route.worker_local_weight_index.should be >= worker_start
            route.worker_local_weight_index.should be < worker_end
          end
        end
      end
    end

    it "assigns unique worker-local weight indices to incoming routes" do
      worker = network.workers[0]

      worker_weight_indices = [] of UInt32

      worker.node_count.times do |worker_local_node_index|
        global_node_index = find_global_node_index(
          network,
          worker.worker_id,
          worker_local_node_index.to_u16!
        )

        next if global_node_index.nil?

        route_range = network.backward_route_range(global_node_index)

        route_range.each do |route_index|
          route = network.backward_routes[route_index]

          worker_weight_indices << route.worker_local_weight_index
        end
      end

      worker_weight_indices.uniq.size.should eq(worker_weight_indices.size)
    end
  end

  describe "shared topology slices" do
    layer_sizes = [4_u16, 3_u16, 2_u16]
    network = AccumulatorNetwork.new(layer_sizes, 8_u8, 0.0)

    it "gives every worker the same forward-route storage" do
      first_worker = network.workers[0]
      second_worker = network.workers[1]

      first_worker.forward_routes.same?(second_worker.forward_routes)
        .should be_true

      first_worker.forward_route_offsets
        .same?(second_worker.forward_route_offsets)
        .should be_true
    end

    it "gives every worker the same backward-route storage" do
      first_worker = network.workers[0]
      second_worker = network.workers[1]

      first_worker.backward_routes.same?(second_worker.backward_routes)
        .should be_true

      first_worker.backward_route_offsets
        .same?(second_worker.backward_route_offsets)
        .should be_true
    end

    it "gives each worker independent mutable node state" do
      first_worker = network.workers[0]
      second_worker = network.workers[1]

      first_worker.nodes.same?(second_worker.nodes)
        .should be_false
    end

    it "gives each worker independent mutable weights" do
      first_worker = network.workers[0]
      second_worker = network.workers[1]

      first_worker.weight_values.same?(second_worker.weight_values)
        .should be_false
    end
  end

  describe "routing and worker iteration regressions" do
    it "gives output-layer nodes empty forward route ranges" do
      network = AccumulatorNetwork.new(
        layer_sizes: [1_u16, 2_u16],
        worker_count: 2,
        layer_latency: 100_u64,
        max_drift: 5000_u64
      )

      network.forward_route_offsets.to_a.should eq [
        0_u32, 2_u32, 2_u32, 2_u32,
      ]

      network.forward_route_range(0_u32).size.should eq 2
      network.forward_route_range(1_u32).size.should eq 0
      network.forward_route_range(2_u32).size.should eq 0
    end

    it "propagates from the processing node rather than its incoming source" do
      network = AccumulatorNetwork.new(
        layer_sizes: [1_u16, 1_u16, 1_u16],
        worker_count: 2,
        layer_latency: 100_u64,
        max_drift: 5000_u64
      )

      # Isolate propagation from the separate offset-construction bug.
      # Correct ranges: input 0...1, hidden 1...2, output 2...2.
      network.forward_route_offsets[0] = 0_u32
      network.forward_route_offsets[1] = 1_u32
      network.forward_route_offsets[2] = 2_u32
      network.forward_route_offsets[3] = 2_u32

      network.reset(10_u64, 250_u64)

      worker = network.worker_for_global_node_index(0_u32)
      input_node = worker.node(0_u16)
      hidden_node = worker.node(1_u16)
      output_node = worker.node(2_u16)

      network.input(0_u16, 90_u64, 0_u64)

      # Process input at 90; schedule hidden at 190.
      worker.iterate.should eq :iterated
      worker.next_tick.should eq 110_u64

      input_node.processed_count.should eq 1
      hidden_node.processed_count.should eq 0
      output_node.processed_count.should eq 0

      # Process hidden at 190; schedule output at 290.
      worker.iterate.should eq :iterated
      worker.next_tick.should eq 210_u64

      hidden_node.processed_count.should eq 1
      output_node.processed_count.should eq 0

      # Wrong source-based routing processes hidden again instead.
      worker.iterate.should eq :iterated
      worker.next_tick.should eq 310_u64

      output_node.processed_count.should eq 1
      hidden_node.processed_count.should eq 1

      # Output-layer processing must not create further events.
      worker.iterate.should eq :iterated
      worker.next_tick.should eq 410_u64

      worker.iterate.should eq :iterated
      worker.next_tick.should eq 450_u64

      worker.iterate.should eq :break

      input_node.processed_count.should eq 1
      hidden_node.processed_count.should eq 1
      output_node.processed_count.should eq 1
    end

    it "returns break on the fourth call after three advances to completion" do
      network = AccumulatorNetwork.new(
        layer_sizes: [1_u16, 1_u16],
        worker_count: 2,
        layer_latency: 100_u64,
        max_drift: 5000_u64
      )
      network.reset(10_u64, 150_u64)

      worker = network.worker_for_global_node_index(0_u32)

      # No events: routing defects cannot affect this timing assertion.
      worker.iterate.should eq :iterated
      worker.next_tick.should eq 110_u64

      worker.iterate.should eq :iterated
      worker.next_tick.should eq 210_u64

      worker.iterate.should eq :iterated
      worker.next_tick.should eq 250_u64

      worker.iterate.should eq :break
      worker.next_tick.should eq 250_u64
    end
  end

  describe "#input" do
    it "routes events to correct worker based on node_id" do
      network = AccumulatorNetwork.new([10_u16, 2_u16], MAX_WORKERS)

      # Node 0 should go to worker 0 (0 % 8 = 0)
      network.input(0_u16, 100_u64, 0_u64)
      # Node 1 should go to worker 1 (1 % 8 = 1)
      network.input(1_u16, 100_u64, 0_u64)
      # Node 8 should go to worker 0 (8 % 8 = 0)
      network.input(8_u16, 100_u64, 0_u64)

      worker_for_node_0 = network.worker_for_global_node_index(0_u16)
      worker_for_node_1 = network.worker_for_global_node_index(1_u16)

      worker_for_node_0.scheduled_events.size.should eq 2
      worker_for_node_1.scheduled_events.size.should eq 1
    end

    it "schedules an event on the correct worker" do
      network = AccumulatorNetwork.new([3_u16, 2_u16], MAX_WORKERS)

      node_id = 1_u16
      process_at = 10_u64
      expected_worker_id = network.node_allocation(node_id).worker_id
      workers = network.workers_for_spec

      network.input(node_id, process_at, 0_u64)

      workers.each do |worker|
        if worker.worker_id == expected_worker_id
          worker.scheduled_events.size.should eq 1
          event = worker.scheduled_events.first
          event.target_local_node_index.should eq 0
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
      network = AccumulatorNetwork.new([1_u16, 1_u16], worker_count: MAX_WORKERS, max_drift: max_drift)
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
      target_node_id = 0_u16
      worker0.schedule(0_u32, target_node_id, 21_u64, 1_u64)
      worker0.schedule(0_u32, target_node_id, 23_u64, 1_u64)
      # Event at t=25 is beyond the safe horizon (24).
      worker0.schedule(0_u32, target_node_id, 25_u64, 1_u64)

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
      network = AccumulatorNetwork.new(layer_sizes: [1_u16, 1_u16], worker_count: 2, layer_latency: 100_u64, max_drift: 5000_u64)
      network.reset(10_u64, 150_u64)
      input_node_id = network.global_node_index(0,0)
      input_node_id.should eq 0
      output_node_id = network.global_node_index(1,0)
      output_node_id.should eq 1
      worker0 = network.worker_for_global_node_index(input_node_id)
      worker0.worker_id.should eq 0
      network.worker_for_global_node_index(output_node_id).worker_id.should eq 0

      input_node_allocation = network.node_allocation(input_node_id)
      input_node_allocation.worker_id.should eq 0
      input_node_allocation.worker_local_node_index.should eq 0
      input_node = worker0.node(input_node_allocation.worker_local_node_index)
      output_node_allocation = network.node_allocation(output_node_id)
      output_node_allocation.worker_id.should eq 0
      output_node_allocation.worker_local_node_index.should eq 1
      output_node = worker0.node(output_node_allocation.worker_local_node_index)
      input_node.processed_count.should eq 0
      input_node.accumulation.should eq 0
      output_node.processed_count.should eq 0
      output_node.accumulation.should eq 0

      worker0.next_tick.should eq 10_u64
      network.horizon_next_tick(0).should eq 110_u64
      network.horizon_next_tick(1).should eq 110_u64

      # Enqueue an input event for node 0 to be processed at time 5.
      process_at = 90_u64
      network.input(input_node_id.to_u16!, process_at, 0_u64)
      # The event should now be scheduled in the clock at time 100.

      # Step time forward to so that the next tick processes the specified time (half open).
      network.horizon_next_tick(1).should eq 110_u64
      result = worker0.iterate
      result.should eq :iterated
      network.horizon_next_tick(0).should eq 210_u64
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

      worker0.iterate.should eq :break
    end


  end


end
