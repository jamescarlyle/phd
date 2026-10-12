require "spec"
require "../src/hierarchical_clock"
require "../src/cross_worker_comm"
require "../src/event"

event_1 = Event.new(10_u32, 0_u64, 1.0)
event_2 = Event.new(20_u32, 1_u64, 2.0)
event_3 = Event.new(30_u32, 2_u64, 3.0)

# describe CrossWorkerMessage do
#   it "initializes with the supplied fields" do
#     message = CrossWorkerMessage.new(12_u32, 8_u64, 2.5)

#     message.target_node.should eq 12_u32
#     message.delay.should eq 8_u64
#     message.payload.should eq 2.5
#   end

#   it "provides zero-valued defaults" do
#     message = CrossWorkerMessage.new

#     message.target_node.should eq 0_u32
#     message.delay.should eq 0_u64
#     message.payload.should eq 0.0
#   end
# end

describe CrossWorkerQueue do
  it "initializes with an empty buffer" do
    queue = CrossWorkerQueue.new
    clock = HierarchicalClock.new
    received = [] of Event

    queue.drain_into(clock)
    1.times { clock.tick { |event| received << event } }

    received.should be_empty
  end

  it "pushes messages into its internal buffer" do
    queue = CrossWorkerQueue.new
    clock = HierarchicalClock.new
    received = [] of Event

    queue.push(event_1)
    queue.push(event_2)
    queue.drain_into(clock)

    2.times { clock.tick { |event| received << event } }

    received.size.should eq 2
    received.map(&.target_node).should contain 10_u32
    received.map(&.target_node).should contain 20_u32
  end

  it "clears the buffer after draining" do
    queue = CrossWorkerQueue.new
    clock = HierarchicalClock.new
    received = [] of Event

    queue.push(event_1)
    queue.drain_into(clock)
    queue.drain_into(clock)

    2.times { clock.tick { |event| received << event } }

    received.size.should eq 1
  end

  it "schedules drained messages at the correct delays" do
    queue = CrossWorkerQueue.new
    clock = HierarchicalClock.new
    received = [] of Event

    queue.push(event_1)
    queue.push(event_2)
    queue.push(event_3)
    queue.drain_into(clock)

    3.times { clock.tick { |event| received << event } }

    received.size.should eq 3
    received.map(&.target_node).should contain 10_u32
    received.map(&.target_node).should contain 20_u32
    received.map(&.target_node).should contain 30_u32
  end
end
