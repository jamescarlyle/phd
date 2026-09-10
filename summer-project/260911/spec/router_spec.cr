require "spec"
require "../src/wheel"
require "../src/cross_worker_comm"
require "../src/worker"
require "../src/node"
require "../src/router"

TEST_WORKER_COUNT = 2

describe Router do
  it "dispatches to every node in the next layer" do
    workers = Array(Worker).new(TEST_WORKER_COUNT) { |id| Worker.new(id, 0_u64, TEST_WORKER_COUNT) }
    bounds = [
      LayerBounds.new(0_u32, 1_u32),
      LayerBounds.new(2_u32, 5_u32),
    ]
    router = Router.new(workers, bounds, TEST_WORKER_COUNT)
    source = Node.new(1_u32, 0)

    router.dispatch(source, 3.5, 0)

    received = [] of Event
    workers.each do |worker|
      worker.drain_all_incoming
      2.times { worker.wheel.tick { |event| received << event } }
    end

    received.size.should eq 4
    received.map(&.target_node).sort.should eq [2_u32, 3_u32, 4_u32, 5_u32]
    received.each { |event| event.payload.should eq 3.5 }
  end

  it "schedules local targets directly on the current worker" do
    workers = Array(Worker).new(TEST_WORKER_COUNT) { |id| Worker.new(id, 0_u64, TEST_WORKER_COUNT) }
    bounds = [
      LayerBounds.new(0_u32, 0_u32),
      LayerBounds.new(2_u32, 2_u32),
    ]
    router = Router.new(workers, bounds, TEST_WORKER_COUNT)
    source = Node.new(0_u32, 0)

    router.dispatch(source, 7.0, 0)

    received = [] of Event
    2.times { workers[0].wheel.tick { |event| received << event } }

    received.size.should eq 1
    received[0].target_node.should eq 2_u32
    received[0].payload.should eq 7.0
  end

  it "enqueues remote targets on their owning workers" do
    workers = Array(Worker).new(TEST_WORKER_COUNT) { |id| Worker.new(id, 0_u64, TEST_WORKER_COUNT) }
    bounds = [
      LayerBounds.new(0_u32, 0_u32),
      LayerBounds.new(1_u32, 1_u32),
    ]
    router = Router.new(workers, bounds, TEST_WORKER_COUNT)
    source = Node.new(0_u32, 0)

    router.dispatch(source, 2.0, 0)

    local_events = [] of Event
    2.times { workers[0].wheel.tick { |event| local_events << event } }
    local_events.should be_empty

    received = [] of Event
    workers[1].drain_all_incoming
    2.times { workers[1].wheel.tick { |event| received << event } }

    received.size.should eq 1
    received[0].target_node.should eq 1_u32
    received[0].payload.should eq 2.0
  end

  it "does nothing when the source is in the final layer" do
    workers = Array(Worker).new(1) { |id| Worker.new(id, 0_u64, 1) }
    bounds = [LayerBounds.new(0_u32, 1_u32)]
    router = Router.new(workers, bounds, 1)
    source = Node.new(0_u32, 0)

    router.dispatch(source, 1.0, 0)

    received = [] of Event
    2.times { workers[0].wheel.tick { |event| received << event } }
    received.should be_empty
  end
end
