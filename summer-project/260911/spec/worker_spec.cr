require "spec"
require "../src/wheel"
require "../src/cross_worker_comm"
require "../src/worker"

describe LayerBounds do
  it "stores the layer boundaries" do
    bounds = LayerBounds.new(10_u32, 99_u32)

    bounds.start_id.should eq 10_u32
    bounds.end_id.should eq 99_u32
  end
end

describe CrossWorkerMessage do
  it "stores its fields" do
    message = CrossWorkerMessage.new(12_u32, 8_u64, 2.5)

    message.target_node.should eq 12_u32
    message.delay.should eq 8_u64
    message.payload.should eq 2.5
  end
end

describe CrossWorkerQueue do
  it "drains messages into a wheel" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.push(12_u32, 1_u64, 2.5)
    queue.push(13_u32, 1_u64, -1.0)
    queue.drain_into(wheel)

    2.times { wheel.tick { |event| received << event } }

    received.size.should eq 2
    received.map(&.target_node).should contain 12_u32
    received.map(&.target_node).should contain 13_u32
    received.map(&.payload).should contain 2.5
    received.map(&.payload).should contain -1.0
  end

  it "clears messages after draining" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.push(1_u32, 1_u64, 1.0)
    queue.drain_into(wheel)
    queue.drain_into(wheel)

    2.times { wheel.tick { |event| received << event } }
    received.size.should eq 1
  end
end

describe Worker do
  it "initializes with its id and current time" do
    worker = Worker.new(3, 42_u64, 1)

    worker.id.should eq 3
    worker.wheel.current_time.should eq 42_u64
    worker.incoming_queues.should_not be_empty
    worker.incoming_queues.should be_a(Array(CrossWorkerQueue))
    worker.incoming_queues.size.should eq(1)
  end

  it "forwards enqueued events to its queue" do
    worker = Worker.new(id: 0, current_time: 0_u64, worker_count: 2)
    received = [] of Event

    worker.enqueue_from(source_id: 1, target_node: 123_u32, delay: 1_u64, payload: 4.5)
    worker.drain_all_incoming
    worker.wheel.tick { |event| received << event }

    received.size.should eq 0
    worker.wheel.tick { |event| received << event }

    received.size.should eq 1
    received[0].target_node.should eq 123_u32
    received[0].payload.should eq 4.5
  end
end
