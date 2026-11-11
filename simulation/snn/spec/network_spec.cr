require "spec"
require "../src/constant"
require "../src/network"
require "../src/worker"
require "./support/worker_schedule_probe"
require "./support/network_probe"
require "./support/spec_helper"

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

  it "allocates uneven layers round-robin across exactly worker_count workers" do
    [1_u8, 3_u8, 8_u8].each do |count|
      net = SpecUtility.network([5_u16, 2_u16, 3_u16], count)
      next_local = Array(UInt32).new(count.to_i32, 0_u32)
      seen = Set(NodeKey).new
      net.layer_nodes.each do |layer|
        layer.each_with_index do |key, i|
          owner = i % count.to_i32
          key.worker_id.should eq(owner.to_u8)
          key.worker_local_node_index.to_u32.should eq(next_local[owner])
          next_local[owner] += 1_u32
          seen.includes?(key).should be_false
          seen << key
        end
      end
      seen.size.should eq(10)
      net.workers.each_with_index do |worker, i|
        worker.node_count.should eq(next_local[i])
      end
    end
  end

  it "uses valid empty sentinels for workers owning no nodes" do
    net = SpecUtility.network([1_u16, 1_u16], 8_u8)
    net.workers[1..7].each do |worker|
      worker.nodes.should be_empty
      worker.forward_route_offsets.to_a.should eq([0_u32])
      worker.backward_route_offsets.to_a.should eq([0_u32])
      worker.forward_routes.should be_empty
      worker.backward_routes.should be_empty
      worker.weight_values.should be_empty
    end
    net.reset(0_u64, 1_u64)
    SpecUtility.drive(net)
    net.workers.all?(&.completed?).should be_true
  end

  it "builds correct per-node degrees and reciprocal route cross-links" do
    sizes = [5_u16, 2_u16, 3_u16]
    net = SpecUtility.network(sizes, 3_u8, weight: 0.75)
    edges = 0
    incoming_edges = 0
    net.layer_nodes.each_with_index do |layer, layer_index|
      layer.each do |source|
        owner = net.workers[source.worker_id]
        outgoing = owner.forward_route_range(source.worker_local_node_index)
        incoming = owner.backward_route_range(source.worker_local_node_index)
        expected_out = layer_index + 1 < sizes.size ? sizes[layer_index + 1].to_i32 : 0
        expected_in = layer_index > 0 ? sizes[layer_index - 1].to_i32 : 0
        outgoing.size.should eq(expected_out)
        incoming.size.should eq(expected_in)
        incoming_edges += incoming.size
        targets = Set(NodeKey).new
        outgoing.each do |f|
          forward = owner.forward_routes[f]
          targets << forward.target_key
          peer = net.workers[forward.target_worker_id]
          b = forward.target_backward_route_index
          peer.backward_route_range(forward.target_worker_local_node_index).includes?(b).should be_true
          backward = peer.backward_routes[b]
          backward.source_key.should eq(source)
          backward.source_forward_route_index.should eq(f)
          backward.worker_local_weight_index.should be < peer.weight_count
          peer.weight_value(backward.worker_local_weight_index).should eq(0.75)
          edges += 1
        end
        if layer_index + 1 < sizes.size
          targets.should eq(net.layer_nodes[layer_index + 1].to_set)
        else
          targets.should be_empty
        end
      end
    end
    edges.should eq(16)
    incoming_edges.should eq(edges)
  end

  it "assigns contiguous local weight indices independently on every worker" do
    net = SpecUtility.network([5_u16, 4_u16, 3_u16], 3_u8, weight: 0.5)
    net.workers.each do |worker|
      indices = worker.backward_routes.map(&.worker_local_weight_index).to_a.sort
      indices.should eq((0...worker.weight_count.to_i32).map(&.to_u32))
      worker.weight_values.size.should eq(worker.backward_routes.size)
    end
  end

  it "supports local node indices beyond a single layer's 4096-node limit" do
    net = SpecUtility.network([4096_u16, 1_u16], 1_u8)
    key = net.layer_nodes[1][0]
    key.should eq(NodeKey.new(0_u8, 4096_u16))
    NodeKey.from_packed_value(key.packed_value).should eq(key)
    net.workers[0].backward_route_range(4096_u16).size.should eq(4096)
  end

  it "rejects per-worker node counts that exceed UInt16 address capacity" do
    layers = [4096_u16, 0_u16] * 17
    expect_raises(ArgumentError) { SpecUtility.network(layers, 1_u8) }
  end

  it "supports disconnected zero-sized intermediate layers" do
    net = SpecUtility.network([2_u16, 0_u16, 2_u16], 3_u8)
    net.workers.each do |worker|
      worker.forward_routes.should be_empty
      worker.backward_routes.should be_empty
      worker.weight_values.should be_empty
    end
    net.reset(0_u64, 1_u64)
    SpecUtility.inject(net, 0, 0, 0_u64).should be_true
    SpecUtility.drive(net)
    SpecUtility.node(net, 2, 0).events.should be_empty
  end

  it "rejects unsupported layer and worker configurations" do
    expect_raises(ArgumentError) { SpecUtility.network([1_u16], 1_u8) }
    expect_raises(ArgumentError) { SpecUtility.network([4097_u16, 1_u16], 1_u8) }
    expect_raises(ArgumentError) { SpecUtility.network([1_u16, 1_u16], 0_u8) }
    expect_raises(ArgumentError) { SpecUtility.network([1_u16, 1_u16], 9_u8) }
  end

  it "injects external input without aliasing incoming route zero" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8)
    net.reset(0_u64, 1_u64)
    net.input(0_u16, 0_u64, 99_u64).should be_true
    SpecUtility.drive(net)
    input = SpecUtility.node(net, 0, 0).events.first
    input.arrival_backward_route_index.should be_nil
    input.payload.should eq(1_u64)
    SpecUtility.node(net, 1, 0).events.first.arrival_backward_route_index.should eq(0_u32)
  end

  it "returns false to external callers when input storage is full" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, capacity: 2_u32)
    net.reset(0_u64, 1_u64)
    net.input(0_u16, 0_u64, 1_u64).should be_true
    net.input(0_u16, 0_u64, 1_u64).should be_true
    net.input(0_u16, 0_u64, 1_u64).should be_false
  end

  it "validates layer-0 indices and the exclusive external input interval" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8)
    net.reset(5_u64, 10_u64)
    expect_raises(IndexError) { net.input(1_u16, 5_u64, 1_u64) }
    expect_raises(ArgumentError) { net.input(0_u16, 4_u64, 1_u64) }
    expect_raises(ArgumentError) { net.input(0_u16, 11_u64, 1_u64) }
  end

  it "drains the pipeline through the final input tick plus all layer latencies" do
    net = SpecUtility.network([1_u16, 1_u16, 1_u16], 1_u8)
    # Latency is 10.
    net.reset(5_u64, 10_u64)
    net.input(0_u16, 9_u64, 1_u64).should be_true
    SpecUtility.drive(net)
    # Event moves through, 9 + 10 + 10 = 29
    SpecUtility.node(net, 2, 0).events.map(&.scheduled_time).should eq([29_u64])
    # Last event specified to be 10, so end_time_exclusive is 10 + 10 + 10 + 1 = 31.
    # Clock will advance till then.
    net.workers[0].next_tick.should eq(31_u64)
    net.sync_mgr.worker_active?(0_u32).should be_false
  end

  it "rejects invalid reset intervals and finish-time arithmetic overflow" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8)
    expect_raises(ArgumentError) { net.reset(10_u64, 9_u64) }
    expect_raises(ArgumentError) { net.reset(UInt64::MAX - 1_u64, UInt64::MAX) }
  end

  it "preserves learned weights across repeated simulations without replaying old events" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, weight: 0.75)
    worker = net.workers[0]
    worker.set_weight_value(0_u32, 2.5)
    3.times do
      net.reset(0_u64, 1_u64)
      net.input(0_u16, 0_u64, 1_u64).should be_true
      SpecUtility.drive(net)
      SpecUtility.node(net, 0, 0).events.size.should eq(1)
      SpecUtility.node(net, 1, 0).events.size.should eq(1)
      worker.weight_value(0_u32).should eq(2.5)
    end
  end

  it "preserves topology backing storage across reset" do
    net = SpecUtility.network
    addresses = net.workers.map do |worker|
      {worker.forward_routes.to_unsafe.address, worker.backward_routes.to_unsafe.address}
    end.to_a
    net.reset(0_u64, 1_u64)
    after = net.workers.map do |worker|
      {worker.forward_routes.to_unsafe.address, worker.backward_routes.to_unsafe.address}
    end.to_a
    after.should eq(addresses)
  end

  it "delivers same-time spikes at the same simulated time independent of worker count" do
    [1_u8, 3_u8, 5_u8, 8_u8].each do |workers|
      net = SpecUtility.network([3_u16, 2_u16, 2_u16], workers: 8_u8, capacity: 16_u32)
      net.reset(0_u64, 1_u64)
      3.times { |i| SpecUtility.inject(net, 0, i, 0_u64).should be_true }
      SpecUtility.drive(net)
      2_u32.times do |i|
        SpecUtility.node(net, 1_u32, i).events.map(&.scheduled_time).should eq([10_u64] * 3)
        SpecUtility.node(net, 2_u32, i).events.map(&.scheduled_time).should eq([20_u64] * 6)
      end
    end
  end

  it "preserves causal fan-out across parallel workers and millisecond boundaries", tags: "stress" do
    net = SpecUtility.network([3_u16, 2_u16, 2_u16], 3_u8, capacity: 64_u32)
    times = [0_u64, 9_u64, 10_u64, 999_u64, 1000_u64, 1001_u64]
    3.times do
      net.reset(0_u64, 1002_u64)
      times.each do |time|
        3.times { |i| SpecUtility.inject(net, 0, i, time).should be_true }
      end
      SpecUtility.parallel_drive(net)
      2_u32.times do |i|
        received = SpecUtility.node(net, 2, i).events
        expected = times.flat_map { |time| [time + 20_u64] * 6 }.sort!
        received.map(&.scheduled_time).sort!.should eq(expected)
        received.map(&.scheduled_time).should eq(received.map(&.scheduled_time).sort!)
        received.each { |event| event.arrival_backward_route_index.should_not be_nil }
      end
      net.workers.all?(&.completed?).should be_true
    end
  end

  describe "with layer sizes [4, 3, 2] and 8 workers" do
    layer_sizes = [4_u16, 3_u16, 2_u16]
    worker_count = 8_u8

    network = AccumulatorNetwork.new(layer_sizes, worker_count, 0.0)

    it "records the requested layer sizes" do
      network.layer_sizes.to_a.should eq(layer_sizes)
    end

    it "computes the total node count" do
      network.total_node_count.should eq(9_u32)
    end

    it "allocates uneven layers round-robin across exactly worker_count workers" do
      [1_u8, 3_u8, 8_u8].each do |count|
        net = SpecUtility.network([5_u16, 2_u16, 3_u16], count)
        next_local = Array(UInt32).new(count.to_i32, 0_u32)
        seen = Set(NodeKey).new
        net.layer_nodes.each do |layer|
          layer.each_with_index do |key, i|
            owner = i % count.to_i32
            key.worker_id.should eq(owner.to_u8)
            key.worker_local_node_index.to_u32.should eq(next_local[owner])
            next_local[owner] += 1_u32
            seen.includes?(key).should be_false
            seen << key
          end
        end
        seen.size.should eq(10)
        net.workers.each_with_index do |worker, i|
          worker.node_count.should eq(next_local[i])
        end
      end
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
  end

  describe "#input" do
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
      worker0.schedule(target_node_id, nil, 21_u64, 1_u64)
      worker0.schedule(target_node_id, nil, 23_u64, 1_u64)
      # Event at t=25 is beyond the safe horizon (24).
      worker0.schedule(target_node_id, nil, 25_u64, 1_u64)

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
      net = AccumulatorNetwork.new([1_u16, 1_u16], worker_count: 2_u8, max_drift: 50_u64, layer_latency: 100_u64)
      net.reset(10_u64, 200_u64)
      net.input(0_u16, 20_u64, 1_u64).should be_true
      worker0 = net.workers[0]
      worker1 = net.workers[1]
      # Both workers are yet to process any events.
      input_node = worker0.nodes[0]
      input_node.processed_count.should eq 0
      output_node = worker0.nodes[1]
      output_node.processed_count.should eq 0

      # Workers are still at the start.
      worker0.next_tick.should eq 10_u64
      worker1.next_tick.should eq 10_u64
      # Their horizons are at current time + max drift from each other.
      net.horizon_next_tick(0).should eq 60_u64
      net.horizon_next_tick(1).should eq 60_u64

      net.input(0_u16, 90_u64, 0_u64)
      # Inputing an event doesn't itself change horizons of either worker.
      input_node.processed_count.should eq 0
      output_node.processed_count.should eq 0
      worker0.next_tick.should eq 10_u64
      worker1.next_tick.should eq 10_u64
      net.horizon_next_tick(0).should eq 60_u64
      net.horizon_next_tick(1).should eq 60_u64

      worker0.iterate.should eq :iterated
      # Worker0 has moved an event through from node1 to node2.
      input_node.processed_count.should eq 1
      output_node.processed_count.should eq 0
      # Worker has moved as far as its horizon.
      worker0.next_tick.should eq 60_u64
      worker1.next_tick.should eq 10_u64
      # Worker0's horizon is bound by its peer's current time.
      net.horizon_next_tick(0).should eq 60_u64
      # Worker1's horizon is bound by worker0's current time.
      net.horizon_next_tick(1).should eq 110_u64

      worker0.iterate.should eq :yield
      # Worker0 cannot yet advance to process the event on node2, since the time will be 20+100.
      input_node.processed_count.should eq 1
      output_node.processed_count.should eq 0
      worker0.next_tick.should eq 60_u64
      worker1.next_tick.should eq 10_u64
      net.horizon_next_tick(0).should eq 60_u64
      net.horizon_next_tick(1).should eq 110_u64
      # At this point, worker0 cannot advance (worker1 next tick is still 10). Time to iterate worker1.

      worker1.iterate.should eq :iterated
      # Worker1 iterated as far as its horizon, but didn't process any events.
      input_node.processed_count.should eq 1
      output_node.processed_count.should eq 0
      worker0.next_tick.should eq 60_u64
      worker1.next_tick.should eq 110_u64
      net.horizon_next_tick(0).should eq 160_u64
      net.horizon_next_tick(1).should eq 110_u64

      worker0.iterate.should eq :iterated
      # Worker0 iterated to its horizon, and processed the 2nd input at 90 and the next layer of 1st input at 120.
      input_node.processed_count.should eq 2
      output_node.processed_count.should eq 1
      worker0.next_tick.should eq 160_u64
      worker1.next_tick.should eq 110_u64
      net.horizon_next_tick(0).should eq 160_u64
      net.horizon_next_tick(1).should eq 210_u64

      worker1.iterate.should eq :iterated
      # Worker1 isn't processing any nodes, so only its clock advances.
      input_node.processed_count.should eq 2
      output_node.processed_count.should eq 1
      worker0.next_tick.should eq 160_u64
      worker1.next_tick.should eq 210_u64
      net.horizon_next_tick(0).should eq 260_u64
      net.horizon_next_tick(1).should eq 210_u64

      worker0.iterate.should eq :iterated
      # Now worker0 can finally process the 2nd event at the 2nd layer 90+100.
      output_node.processed_count.should eq 2
      worker0.next_tick.should eq 260_u64

      worker1.iterate.should eq :iterated
      # worker1 advances to the finish time (last event time + layers*latency + 1) = 200 + 100
      worker1.next_tick.should eq 301_u64

      worker0.iterate.should eq :iterated
      # worker0 advances to the finish time (last event time + layers*latency + 1) = 200 + 100
      worker0.next_tick.should eq 301_u64

      worker0.iterate.should eq :break
      # worker0 can't advance further; break
      worker1.iterate.should eq :break

    end
  end
end
