require "spec"
require "../src/type"
require "../src/clock"

alias AccumulatorClock = Clock(UInt64)
alias LIFClock = Clock(Float64)

describe Clock do

  it "allows producers to schedule events into individual slot buffers" do
    # Explicitly specialize Clock for unsigned integer payloads
    clock = AccumulatorClock.new(slot_capacity: 16)
    clock.should be_a(AccumulatorClock)
  end

  it "operates with floating-point payloads" do
    # Explicitly specialize Clock for floating-point payloads
    clock = LIFClock.new(slot_capacity: 16)
    clock.should be_a(LIFClock)
  end

  it "operates with the active compile-time payload alias" do
    # Specialize using the active simulation payload
    clock = Clock(ActivePayload).new(slot_capacity: 16)
    clock.should be_a(Clock(ActivePayload))
  end

  it "is able to be reset" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    clock.reset(0, 99)
    clock.next_tick.should eq 0
    clock.completed?.should be_false
    clock.advance_to(100)
    clock.completed?.should be_true
  end

  it "allows producers to schedule events into individual slot buffers" do
    clock = AccumulatorClock.new(slot_capacity: 16)

    clock.schedule(Event.new(1_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event.new(2_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event.new(3_u32, 8_u64, 1_u64)).should be_true

    5.times { clock.tick.should be_empty }

    events_at_5 = clock.tick
    events_at_5.size.should eq(2)
    events_at_5.map(&.target_local_node_idx).should eq([1_u32, 2_u32])

    2.times { clock.tick.should be_empty }

    events_at_8 = clock.tick
    events_at_8.size.should eq(1)
    events_at_8.first.target_local_node_idx.should eq(3_u32)
  end

  it "cascades events from level-1 millisecond slot buffers to level-0 microsecond slot buffers" do
    clock = AccumulatorClock.new(slot_capacity: 16)

    clock.schedule(Event.new(101_u32, 1_250_u64, 1_u64)).should be_true

    dispatched = clock.advance_to(1_000_u64)
    dispatched.should be_empty
    clock.next_tick.should eq(1_000_u64)

    dispatched_later = clock.advance_to(1_251_u64)
    dispatched_later.size.should eq(1)
    dispatched_later.first.target_local_node_idx.should eq(101_u32)
    clock.next_tick.should eq(1_251_u64)
  end

  it "covers 1 second in microsecond increments without loss" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    target_time = 999_999_u64

    clock.schedule(Event.new(201_u32, target_time, 1_u64)).should be_true

    dispatched = clock.advance_to(target_time)
    dispatched.should be_empty

    final_tick = clock.tick
    final_tick.size.should eq(1)
    final_tick.first.target_local_node_idx.should eq(201_u32)
    clock.next_tick.should eq(1_000_000_u64)
  end

  it "supports multiple concurrent producers scheduling while the owner ticks forward" do
    clock = AccumulatorClock.new(slot_capacity: 128)
    producers = 4
    events_per_producer = 250
    done = Channel(Nil).new

    producers.times do |p|
      spawn do
        events_per_producer.times do |i|
          target = 200_u64 + ((i * 2 + p) % 600).to_u64
          event = Event.new((p * 10_000 + i).to_u32, target, 1_u64)
          loop do
            break if clock.schedule(event)
            Fiber.yield
          end
        end
        done.send(nil)
      end
    end

    collected = Array(Event(ActivePayload)).new
    spawn do
      1_000.times do
        batch = clock.tick
        collected.concat(batch) unless batch.empty?
        Fiber.yield
      end
      done.send(nil)
    end

    (producers + 1).times { done.receive }

    remaining = clock.advance_to(1_000_u64)
    collected.concat(remaining)

    collected.size.should eq(producers * events_per_producer)
  end

  it "raises when scheduling exceeds the one-second horizon" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    expect_raises(ArgumentError, /beyond 1-second capacity/) do
      clock.schedule(Event.new(301_u32, 1_000_000_u64, 1_u64))
    end
  end
end
