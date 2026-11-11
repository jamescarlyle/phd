require "spec"
require "../src/buffer"

alias AccumulatorBuffer = Buffer(UInt64)

private def make_event(time : UInt64) : Event(UInt64)
  Event(UInt64).new(0_u16, nil, time, 1_u64)
end

private def fill_and_drain(buffer : Buffer(UInt64), start_sequence : UInt64, count : UInt32) : Nil
  count.times do |offset|
    accepted = buffer.push(make_event(start_sequence + offset))
    accepted.should be_true
  end

  buffer.size.should eq(count)

  count.times do
    event = buffer.pop
    event.should_not be_nil
  end

  buffer.size.should eq(0)
  buffer.drained?.should be_true
end

describe Buffer do

  it "requires a positive power-of-two capacity" do
    [0_u32, 1_u32, 3_u32, 6_u32].each do |capacity|
      expect_raises(ArgumentError) { Buffer(UInt64).new(capacity) }
    end
  end

  it "starts empty and exposes no dummy event" do
    buffer = Buffer(UInt64).new(2)
    buffer.empty?.should be_true
    buffer.size.should eq(0_u32)
    buffer.pop.should be_nil
  end

  it "uses every slot, reports full, and does not evict accepted events" do
    buffer = Buffer(UInt64).new(2)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 10_u64)).should be_true
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 11_u64)).should be_true
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 12_u64)).should be_false
    buffer.size.should eq(2_u32)
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(10_u64)
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(11_u64)
    buffer.pop.should be_nil
  end

  it "rejects capacity one" do
    expect_raises(ArgumentError) { Buffer(UInt64).new(1) }
  end

  it "supports capacity one through repeated full/empty transitions" do
    buffer = Buffer(UInt64).new(2)
    20_u64.times do |i|
      buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, i)).should be_true
      buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, i)).should be_true
      buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, i)).should be_false
      buffer.pop || raise "Expected a queued event"
      popped = buffer.pop || raise "Expected a queued event"
      popped.payload.should eq(i.to_u64)
      buffer.pop.should be_nil
    end
  end

  it "allows quiescent clear and reuse without exposing pre-reset events" do
    buffer = Buffer(UInt64).new(2)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 99_u64)).should be_true
    buffer.clear
    buffer.empty?.should be_true
    buffer.size.should eq(0_u32)
    buffer.pop.should be_nil
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 7_u64)).should be_true
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(7_u64)
  end

  it "pushes and pops elements in FIFO order" do
    buffer = AccumulatorBuffer.new(4)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 100_u64, 10)).should be_true
    buffer.push(Event(UInt64).new(2_u16, 2_u32, 200_u64, 20)).should be_true

    e1 = buffer.pop
    e1.should_not be_nil
    e1.as(Event).target_local_node_index.should eq(1_u16)
    e1.as(Event).arrival_backward_route_index.should eq(1_u32)

    e2 = buffer.pop
    e2.should_not be_nil
    e2.as(Event).target_local_node_index.should eq(2_u16)
    e1.as(Event).arrival_backward_route_index.should eq(1_u32)

    buffer.pop.should be_nil
  end

  it "returns false when buffer capacity is saturated" do
    buffer = Buffer(UInt64).new(2)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, 1_u64)).should be_true
    buffer.push(Event(UInt64).new(2_u16, 2_u32, 20_u64, 1_u64)).should be_true
    buffer.push(Event(UInt64).new(3_u16, 3_u32, 30_u64, 1_u64)).should be_false
  end

  it "handles multiple concurrent producers without loss" do
    buffer = Buffer(UInt64).new(8192)
    producers = 4
    events_per_producer = 1000
    done = Channel(Nil).new

    producers.times do |p|
      spawn do
        events_per_producer.times do |i|
          id = (p * events_per_producer + i).to_u16
          loop do
            break if buffer.push(Event.new(id, id.to_u32, 1_u64, 1_u64))
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

  it "publishes every accepted MPSC event exactly once", tags: "stress" do
    buffer = Buffer(UInt64).new(8)
    stopped = Atomic(Bool).new(false)
    results = Channel(Exception?).new(4)
    4.times do |producer|
      spawn do
        error : Exception? = nil
        begin
          128.times do |i|
            event = Event(UInt64).new(1_u16, 1_u32, 10_u64, (producer * 128 + i).to_u64)
            attempts = 0
            until buffer.push(event)
              raise "Producer cancelled" if stopped.get
              attempts += 1
              raise "Producer retry bound exceeded" if attempts > 1_000_000
              Fiber.yield
            end
          end
        rescue ex : Exception
          error = ex
        ensure
          results.send(error)
        end
      end
    end
    seen = Set(UInt64).new
    deadline = Time.instant + 10.seconds
    begin
      until seen.size == 512
        raise "MPSC drain timeout" if Time.instant > deadline
        if event = buffer.pop
          seen.includes?(event.payload).should be_false
          seen << event.payload
        else
          Fiber.yield
        end
      end
      4.times do
        select
        when error = results.receive
          raise error if error
        when timeout(10.seconds)
          raise "Producer completion timeout"
        end
      end
      seen.should eq((0...512).map(&.to_u64).to_set)
      buffer.pop.should be_nil
    ensure
      stopped.set(true)
    end
  end
end

# Cell is private. Publication and sequence recycling are tested via Buffer.
describe "Buffer::Cell (private publication contract)" do
  it "recycles cell generations across many ring wraps without stale payloads" do
    buffer = Buffer(UInt64).new(2)
    1000.times do |cycle|
      first = (cycle * 2).to_u64
      buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, first)).should be_true
      buffer.push(Event(UInt64).new(1_u16, nil, 10_u64, first + 1_u64)).should be_true
      a = buffer.pop || raise "Expected a queued event"
      b = buffer.pop || raise "Expected a queued event"
      a.payload.should eq(first)
      a.arrival_backward_route_index.should eq(1_u32)
      b.payload.should eq(first + 1_u64)
      b.arrival_backward_route_index.should be_nil
      buffer.pop.should be_nil
    end
  end

  it "does not publish a failed push into the next cell generation" do
    buffer = Buffer(UInt64).new(2)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, 1_u64)).should be_true
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, 2_u64)).should be_true
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, 999_u64)).should be_false
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(1_u64)
    buffer.push(Event(UInt64).new(1_u16, 1_u32, 10_u64, 3_u64)).should be_true
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(2_u64)
    popped = buffer.pop || raise "Expected a queued event"
    popped.payload.should eq(3_u64)
    buffer.pop.should be_nil
  end

  describe "#drained?" do
    it "reports a new buffer as drained" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      buffer.drained?.should be_true
      buffer.size.should eq(0)
    end

    it "reports a partially filled buffer as not drained" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      buffer.push(make_event(0)).should be_true

      buffer.drained?.should be_false
      buffer.size.should eq(1)
    end

    it "reports a fully drained buffer as drained" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      1024_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      1024.times do
        buffer.pop.should_not be_nil
      end

      buffer.drained?.should be_true
      buffer.size.should eq(0)
    end
  end

  describe "reuse without clear" do
    it "accepts another full capacity after one complete fill-and-drain cycle" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      fill_and_drain(buffer, 0, 1024)

      1024_u64.times do |offset|
        accepted = buffer.push(make_event(1024_u64 + offset))
        accepted.should be_true, "expected reuse without clear at offset #{offset}"
      end

      buffer.size.should eq(1024)

      1024.times do
        buffer.pop.should_not be_nil
      end

      buffer.drained?.should be_true
    end

    it "accepts repeated fill-and-drain cycles without clear" do
      buffer = Buffer(UInt64).new(capacity: 1024)
      cycles = 8

      cycles.times do |cycle|
        start_sequence = cycle.to_u64 * 1024

        fill_and_drain(buffer, start_sequence, 1024)
      end

      buffer.drained?.should be_true
      buffer.size.should eq(0)
    end

    it "preserves FIFO order across a wraparound without clear" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      1024_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      1024.times do |offset|
        event = buffer.pop
        event.should_not be_nil
        event.try(&.scheduled_time).should eq(offset)
      end

      1024_u64.times do |offset|
        expected_time = 1024_u64 + offset
        buffer.push(make_event(expected_time)).should be_true
      end

      1024.times do |offset|
        event = buffer.pop
        event.should_not be_nil
        event.try(&.scheduled_time).should eq(1024 + offset)
      end

      buffer.drained?.should be_true
    end

    it "supports partial fill-and-drain cycles without clear" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      4.times do |cycle|
        start_sequence = cycle.to_u64 * 257

        257_u64.times do |offset|
          buffer.push(make_event(start_sequence + offset)).should be_true
        end

        257.times do
          buffer.pop.should_not be_nil
        end

        buffer.drained?.should be_true
      end

      buffer.size.should eq(0)
    end

    it "does not accept an event after filling capacity without pops" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      1024_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      buffer.push(make_event(1024)).should be_false
      buffer.size.should eq(1024)
    end

    it "accepts the wrapped event after all capacity entries are popped" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      1024_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      buffer.push(make_event(1024)).should be_false

      1024.times do
        buffer.pop.should_not be_nil
      end

      buffer.push(make_event(1024_u64)).should be_true
      buffer.size.should eq(1)

      event = buffer.pop
      event.should_not be_nil
      event.try(&.scheduled_time).should eq(1024)

      buffer.drained?.should be_true
    end
  end

  describe "clear remains available for recovery" do
    it "resets a non-empty buffer to empty" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      10_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      buffer.clear

      buffer.drained?.should be_true
      buffer.size.should eq(0)
    end

    it "accepts a full capacity immediately after clear" do
      buffer = Buffer(UInt64).new(capacity: 1024)

      1024_u64.times do |offset|
        buffer.push(make_event(offset)).should be_true
      end

      buffer.clear

      1024_u64.times do |offset|
        buffer.push(make_event(1024_u64 + offset)).should be_true
      end

      buffer.size.should eq(1024)
    end
  end
end
