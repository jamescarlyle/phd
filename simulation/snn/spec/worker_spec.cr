require "spec"
require "./support/spec_helper"
require "../src/constant"
require "../src/network"
require "../src/worker"


describe WorkerState do
  it "starts inactive at tick zero" do
    state = WorkerState.new
    state.active?.should be_false
    state.next_tick.should eq(0_u64)
  end

  it "retains updates to atomic progress and activity" do
    state = WorkerState.new(true, 7_u64)
    state.next_tick = 99_u64
    state.active = false
    state.next_tick.should eq(99_u64)
    state.active?.should be_false
  end

  it "keeps progress slots isolated inside SyncManager storage" do
    mgr = SyncManager.new(3_u32, 10_u64, 9_u64)
    mgr.reset(0_u64, 100_u64)
    mgr.record_progress(1_u32, 7_u64)
    mgr.worker_next_tick(0_u32).should eq(0_u64)
    mgr.worker_next_tick(1_u32).should eq(7_u64)
    mgr.worker_next_tick(2_u32).should eq(0_u64)
  end
end

describe Worker do
  describe "with a worker owning two nodes and three weights" do
    network = AccumulatorNetwork.new([4_u16, 3_u16, 2_u16], 8_u8, 0.0)
    worker = network.workers[0]

    it "initialises all node states to zero" do
      worker.nodes.to_a.each do |node|
        node.accumulation.should eq(0.0)
      end
    end

    it "initialises all weights to the requested value" do
      worker.weight_values.to_a.each do |weight_value|
        weight_value.should eq(0.0)
      end
    end

    it "reads and writes a weight value" do
      worker.set_weight_value(0_u32, 1.5)
      worker.weight_value(0_u32).should eq(1.5)
    end

    it "adds to a weight value" do
      worker.set_weight_value(1_u32, 2.0)
      worker.add_to_weight_value(1_u32, 0.25)
      worker.weight_value(1_u32).should eq(2.25)
    end

    it "resets node states" do
      node = worker.node(0_u16)
      node.process(Event.new(0_u32, 0_u16, 0_u64, 0_u64))
      worker.node(0_u16).processed_count.should eq(1)
      worker.reset_nodes
      worker.node(0_u16).processed_count.should eq(0)
    end

    it "resets weight values" do
      worker.set_weight_value(2_u32, 9.0)
      worker.reset_weight_values
      worker.weight_value(2_u32).should eq(0.0)
    end
  end

  it "retains a valid network reference and uses worker-local node access" do
    net = SpecUtility.network([3_u16, 2_u16], 2_u8)
    net.workers.each do |worker|
      worker.network.same?(net).should be_true
      worker.nodes.size.should eq(worker.node_count.to_i32)
      worker.node(0_u16).same?(worker.nodes[0]).should be_true
    end
  end

  it "uses local offset arrays with one final sentinel per worker" do
    net = SpecUtility.network([3_u16, 2_u16, 1_u16], 2_u8)
    net.workers.each do |worker|
      worker.forward_route_offsets.size.should eq(worker.nodes.size + 1)
      worker.backward_route_offsets.size.should eq(worker.nodes.size + 1)
      worker.forward_route_offsets[0].should eq(0_u32)
      worker.backward_route_offsets[0].should eq(0_u32)
      worker.forward_route_offsets.last.should eq(worker.forward_routes.size.to_u32)
      worker.backward_route_offsets.last.should eq(worker.backward_routes.size.to_u32)
    end
  end

  it "returns Bool from schedule and reports overload without losing queued events" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, capacity: 2_u32)
    net.reset(0_u64, 1_u64)
    worker = net.workers[0]
    worker.schedule(0_u16, nil, 0_u64, 4_u64).should be_true
    worker.schedule(0_u16, nil, 0_u64, 5_u64).should be_true
    worker.schedule(0_u16, nil, 0_u64, 6_u64).should be_false
    SpecUtility.drive(net)
    SpecUtility.node(net, 0, 0).events.map(&.payload).sort!.should eq([4_u64, 5_u64])
  end

  it "fans out from the processed local node rather than the received event's source" do
    net = SpecUtility.network([1_u16, 1_u16, 1_u16], 1_u8)
    net.reset(0_u64, 1_u64)
    SpecUtility.inject(net, 0, 0, 0_u64, 99_u64).should be_true
    SpecUtility.drive(net)
    SpecUtility.node(net, 0, 0).events.map(&.payload).should eq([99_u64])
    SpecUtility.node(net, 1, 0).events.map(&.scheduled_time).should eq([10_u64])
    SpecUtility.node(net, 2, 0).events.map(&.scheduled_time).should eq([20_u64])
    SpecUtility.node(net, 1, 0).events.map(&.payload).should eq([1_u64])
    SpecUtility.node(net, 2, 0).events.map(&.payload).should eq([1_u64])
  end

  it "preserves an incoming route handle on cross-worker delivery" do
    net = SpecUtility.network([1_u16, 2_u16], 2_u8)
    net.reset(0_u64, 1_u64)
    SpecUtility.inject(net, 0, 0, 0_u64).should be_true
    SpecUtility.drive(net)
    source = net.layer_nodes[0][0]
    key = net.layer_nodes[1][1]
    key.worker_id.should_not eq(source.worker_id)
    worker = net.workers[key.worker_id]
    event = worker.node(key.worker_local_node_index).events.first
    incoming = event.arrival_backward_route_index.not_nil!
    worker.backward_route_range(key.worker_local_node_index).includes?(incoming).should be_true
    worker.backward_routes[incoming].source_key.should eq(source)
    event.target_local_node_index.should eq(key.worker_local_node_index)
  end

  it "does not directly mutate the peer node while enqueueing a delivery" do
    net = SpecUtility.network([1_u16, 2_u16], 2_u8)
    net.reset(0_u64, 1_u64)
    SpecUtility.inject(net, 0, 0, 0_u64).should be_true
    source_worker = net.workers[net.layer_nodes[0][0].worker_id]
    source_worker.iterate.should eq(:iterated)
    SpecUtility.node(net, 1, 1).events.should be_empty
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 1).events.size.should eq(1)
  end

  it "suppresses output for false Bool and emits a unit payload for true Bool" do
    net = SpecUtility.gate_network
    net.reset(0_u64, 1_u64)
    source = SpecUtility.node(net, 0, 0)
    net.workers[0].schedule(0_u16, nil, 0_u64, 0.25).should be_true
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 0).events.should be_empty
    net.reset(0_u64, 1_u64)
    source.emit = true
    net.workers[0].schedule(0_u16, nil, 0_u64, 0.25).should be_true
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 0).events.map(&.payload).should eq([1.0])
  end

  it "yields without moving its clock when a peer limits its horizon" do
    net = SpecUtility.network
    net.reset(0_u64, 100_u64)
    worker = net.workers[0]
    worker.iterate.should eq(:iterated)
    before = worker.next_tick
    worker.iterate.should eq(:yield)
    worker.next_tick.should eq(before)
    net.sync_mgr.worker_next_tick(0_u32).should eq(before)
  end

  it "breaks repeatedly without advancing once completed" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8)
    net.reset(0_u64, 1_u64)
    SpecUtility.drive(net)
    worker = net.workers[0]
    before = worker.next_tick
    3.times { worker.iterate.should eq(:break) }
    worker.next_tick.should eq(before)
  end

  it "rejects invalid node and incoming-route indices before enqueueing" do
    net = SpecUtility.network
    net.reset(0_u64, 1_u64)
    worker = net.workers[0]
    expect_raises(IndexError) { worker.schedule(UInt16::MAX, nil, 0_u64, 1_u64) }
    key = net.layer_nodes[1][0]
    owner = net.workers[key.worker_id]
    expect_raises(IndexError) do
      owner.schedule(key.worker_local_node_index, UInt32::MAX, 0_u64, 1_u64)
    end
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 0).events.should be_empty
  end

  it "rejects an incoming route that belongs to another local node" do
    net = SpecUtility.network([1_u16, 2_u16], 1_u8)
    net.reset(0_u64, 1_u64)
    a = net.layer_nodes[1][0]
    b = net.layer_nodes[1][1]
    worker = net.workers[0]
    b_route = worker.backward_route_range(b.worker_local_node_index).begin
    expect_raises(ArgumentError) do
      worker.schedule(a.worker_local_node_index, b_route, 0_u64, 1_u64)
    end
  end

  it "raises on failed internal delivery and does not publish successful progress" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, capacity: 2_u32)
    net.reset(0_u64, 1_u64)
    worker = net.workers[0]
    target = net.layer_nodes[1][0]
    worker.schedule(target.worker_local_node_index, nil, 10_u64, 7_u64).should be_true
    worker.schedule(target.worker_local_node_index, nil, 10_u64, 8_u64).should be_true
    worker.schedule(0_u16, nil, 0_u64, 1_u64).should be_true
    expect_raises(RuntimeError, "Worker 0 can't accept event for 1 at 10")  { worker.iterate }
    net.sync_mgr.worker_next_tick(0_u32).should eq(0_u64)
  end

  it "can recover from overload only after a quiescent reset clears pending deliveries" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, capacity: 2_u32)
    net.reset(0_u64, 1_u64)
    worker = net.workers[0]
    worker.schedule(1_u16, nil, 10_u64, 7_u64).should be_true
    worker.schedule(1_u16, nil, 10_u64, 8_u64).should be_true
    worker.schedule(0_u16, nil, 0_u64, 1_u64).should be_true
    expect_raises(RuntimeError, "Worker 0 can't accept event for 1 at 10") do
      net.run
    end
    net.reset(0_u64, 1_u64)
    SpecUtility.inject(net, 0, 0, 0_u64).should be_true
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 0).events.map(&.payload).should eq([1_u64])
  end

  it "keeps local weights isolated and supports explicit weight reset values" do
    net = SpecUtility.network(weight: 0.75)
    a = net.workers[0]
    b = net.workers[1]
    a.set_weight_value(0_u32, 2.0)
    a.add_to_weight_value(0_u32, 0.5)
    a.weight_value(0_u32).should eq(2.5)
    b.weight_value(0_u32).should eq(0.75)
    a.reset_weight_values(0.25)
    a.weight_values.all? { |value| value == 0.25 }.should be_true
    b.weight_value(0_u32).should eq(0.75)
  end

  it "reset clears node state and pending events but preserves learned weights" do
    net = SpecUtility.network([1_u16, 1_u16], 1_u8, weight: 0.5)
    net.reset(0_u64, 1_u64)
    worker = net.workers[0]
    worker.set_weight_value(0_u32, 3.0)
    SpecUtility.inject(net, 0, 0, 0_u64).should be_true
    worker.iterate
    SpecUtility.node(net, 0, 0).events.size.should eq(1)
    # Call worker reset to clear buffer explicitly, because network @failed is not set.
    worker.reset(0_u64, 1_u64, true)
    net.reset(0_u64, 1_u64)
    worker.weight_value(0_u32).should eq(3.0)
    SpecUtility.drive(net)
    SpecUtility.node(net, 0, 0).events.should be_empty
    SpecUtility.node(net, 1, 0).events.should be_empty
  end

  it "fails explicitly on a full peer queue after partial fan-out without publishing progress" do
    net = SpecUtility.network([1_u16, 2_u16], 2_u8, capacity: 2_u32)
    net.reset(0_u64, 1_u64)
    source = net.workers[0]
    peer_key = net.layer_nodes[1][1]
    peer = net.workers[peer_key.worker_id]
    peer.schedule(peer_key.worker_local_node_index, nil, 10_u64, 7_u64).should be_true
    peer.schedule(peer_key.worker_local_node_index, nil, 10_u64, 8_u64).should be_true
    source.schedule(0_u16, nil, 0_u64, 1_u64).should be_true
    expect_raises(RuntimeError, "Worker 1 can't accept event for 0 at 10")  { source.iterate }
    net.sync_mgr.worker_next_tick(0_u32).should eq(0_u64)
    peer.node(peer_key.worker_local_node_index).events.should be_empty
    # Explicitly clear the worker clock buffers, since @cancelled will not trigger it.
    source.reset(0_u64, 1_u64, true)
    peer.reset(0_u64, 1_u64, true)
    net.reset(0_u64, 1_u64)
    SpecUtility.drive(net)
    SpecUtility.node(net, 1, 0).events.should be_empty
    SpecUtility.node(net, 1, 1).events.should be_empty
  end


end
