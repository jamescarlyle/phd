require "spec"
require "../src/buffer"

alias AccumulatorBuffer = Buffer(UInt64)

describe Buffer do
  it "pushes and pops elements in FIFO order" do
    buffer = AccumulatorBuffer.new(4)
    buffer.push(Event(UInt64).new(1_u32, 1_u16, 100_u64, 10)).should be_true
    buffer.push(Event(UInt64).new(2_u32, 2_u16, 200_u64, 20)).should be_true

    e1 = buffer.pop
    e1.should_not be_nil
    e1.as(Event).source_global_node_index.should eq(1_u32)
    e1.as(Event).target_local_node_index.should eq(1_u16)

    e2 = buffer.pop
    e2.should_not be_nil
    e2.as(Event).source_global_node_index.should eq(2_u32)
    e2.as(Event).target_local_node_index.should eq(2_u16)

    buffer.pop.should be_nil
  end

  it "returns false when buffer capacity is saturated" do
    buffer = Buffer(UInt64).new(2)
    buffer.push(Event(UInt64).new(1_u32, 1_u16, 10_u64, 1_u64)).should be_true
    buffer.push(Event(UInt64).new(2_u32, 2_u16, 20_u64, 1_u64)).should be_true
    buffer.push(Event(UInt64).new(3_u32, 3_u16, 30_u64, 1_u64)).should be_false
  end

  it "handles multiple concurrent producers without loss" do
    buffer = Buffer(UInt64).new(8192)
    producers = 4
    events_per_producer = 1000
    done = Channel(Nil).new

    producers.times do |p|
      spawn do
        events_per_producer.times do |i|
          id = (p * events_per_producer + i).to_u32
          loop do
            break if buffer.push(Event.new(id, id.to_u16, 1_u64, 1_u64))
            Fiber.yield
          end
        end
        done.send(nil)
      end
    end

    producers.times { done.receive }

    received = Set(UInt64).new
    while event = buffer.pop
      received.add(event.target_local_node_index)
    end

    received.size.should eq(producers * events_per_producer)
  end
end
