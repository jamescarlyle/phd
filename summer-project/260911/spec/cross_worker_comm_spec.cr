require "spec"
require "../src/wheel"
require "../src/cross_worker_comm"

describe CrossWorkerMessage do
  it "initializes with the supplied fields" do
    message = CrossWorkerMessage.new(12_u32, 8_u64, 2.5)

    message.target_node.should eq 12_u32
    message.delay.should eq 8_u64
    message.payload.should eq 2.5
  end

  it "provides zero-valued defaults" do
    message = CrossWorkerMessage.new

    message.target_node.should eq 0_u32
    message.delay.should eq 0_u64
    message.payload.should eq 0.0
  end
end

describe CrossWorkerQueue do
  it "initializes with an empty buffer" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.drain_into(wheel)
    1.times { wheel.tick { |event| received << event } }

    received.should be_empty
  end

  it "pushes messages into its internal buffer" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.push(1_u32, 1_u64, 1.0)
    queue.push(2_u32, 1_u64, -1.0)
    queue.drain_into(wheel)

    2.times { wheel.tick { |event| received << event } }

    received.size.should eq 2
    received.map(&.target_node).should contain 1_u32
    received.map(&.target_node).should contain 2_u32
  end

  it "clears the buffer after draining" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.push(1_u32, 1_u64, 1.0)
    queue.drain_into(wheel)
    queue.drain_into(wheel)

    2.times { wheel.tick { |event| received << event } }

    received.size.should eq 1
  end

  it "schedules drained messages at the correct delays" do
    queue = CrossWorkerQueue.new
    wheel = HierarchicalWheel.new
    received = [] of Event

    queue.push(10_u32, 0_u64, 1.0)
    queue.push(20_u32, 1_u64, 2.0)
    queue.push(30_u32, 2_u64, 3.0)
    queue.drain_into(wheel)

    3.times { wheel.tick { |event| received << event } }

    received.size.should eq 3
    received.map(&.target_node).should contain 10_u32
    received.map(&.target_node).should contain 20_u32
    received.map(&.target_node).should contain 30_u32
  end
end
