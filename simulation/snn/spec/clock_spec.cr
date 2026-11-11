require "spec"
require "../src/clock"

alias AccumulatorClock = Clock(UInt64)
alias LIFClock = Clock(Float64)
alias ActivePayload = UInt64

describe Clock do
  it "operates with unsigned integer payloads" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    clock.should be_a(AccumulatorClock)
  end

  it "operates with floating-point payloads" do
    clock = LIFClock.new(slot_capacity: 16)
    clock.should be_a(LIFClock)
  end

  it "operates with the active compile-time payload alias" do
    clock = Clock(ActivePayload).new(slot_capacity: 16)
    clock.should be_a(Clock(ActivePayload))
  end

  it "is able to be reset" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    clock.reset(0_u64, 99_u64, false)
    clock.next_tick.should eq(0_u64)
    clock.completed?.should be_false
    clock.advance_to(100_u64) do |_event|
      fail "Unexpected event while advancing an empty clock"
    end
    clock.completed?.should be_true
  end

  it "allows producers to schedule events into individual slot buffers" do
    clock = AccumulatorClock.new(slot_capacity: 16)

    clock.schedule(Event.new(1_u16, 1_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event.new(2_u16, 2_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event.new(3_u16, 3_u32, 8_u64, 1_u64)).should be_true

    5.times do
      clock.tick do |_event|
        fail "Event dispatched before tick 5"
      end
    end

    targets_at_5 = Array(UInt16).new(2)
    clock.tick do |event|
      targets_at_5 << event.target_local_node_index
      nil
    end
    targets_at_5.should eq([1_u16, 2_u16])

    2.times do
      clock.tick do |_event|
        fail "Event dispatched between ticks 5 and 8"
      end
    end

    dispatched = 0
    clock.tick do |event|
      event.target_local_node_index.should eq(3_u16)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
  end

  it "cascades events from level-1 millisecond slot buffers to level-0 microsecond slot buffers" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    clock.schedule(Event.new(101_u16, 101_u32, 1_250_u64, 1_u64)).should be_true

    clock.advance_to(1_000_u64) do |_event|
      fail "Event dispatched before the cascade boundary"
    end
    clock.next_tick.should eq(1_000_u64)

    dispatched = 0
    clock.advance_to(1_251_u64) do |event|
      event.target_local_node_index.should eq(101_u16)
      event.scheduled_time.should eq(1_250_u64)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
    clock.next_tick.should eq(1_251_u64)
  end

  it "covers 1 second in microsecond increments without loss" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    target_time = 999_999_u64
    clock.schedule(Event.new(201_u16, 201_u32, target_time, 1_u64)).should be_true

    clock.advance_to(target_time) do |_event|
      fail "Event dispatched before its scheduled time"
    end

    dispatched = 0
    clock.tick do |event|
      event.target_local_node_index.should eq(201_u16)
      event.scheduled_time.should eq(target_time)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
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
          event = Event.new((p * 10_000 + i).to_u16, (p * 10_000 + i).to_u32, target, 1_u64)
          loop do
            break if clock.schedule(event)
            Fiber.yield
          end
        end
        done.send(nil)
      end
    end

    collected = 0
    spawn do
      1_000.times do
        clock.tick do |_event|
          collected += 1
          nil
        end
        Fiber.yield
      end
      done.send(nil)
    end

    (producers + 1).times { done.receive }

    clock.advance_to(1_000_u64) do |_event|
      collected += 1
      nil
    end
    collected.should eq(producers * events_per_producer)
  end

  it "raises when scheduling exceeds the one-second horizon" do
    clock = AccumulatorClock.new(slot_capacity: 16)
    expect_raises(ArgumentError, /beyond 1-second capacity/) do
      clock.schedule(Event.new(301_u16, 301_u32, 1_000_000_u64, 1_u64))
    end
  end

  it "accepts an event exactly at next_tick and dispatches it once" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(150_u64, 1000_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 150_u64, 1_u64)).should be_true

    dispatched = 0
    clock.tick do |event|
      event.scheduled_time.should eq(150_u64)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
    clock.next_tick.should eq(151_u64)
    clock.tick do |_event|
      fail "Event dispatched more than once"
    end
  end

  it "rejects past events instead of silently retiming them" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(150_u64, 1000_u64, false)
    expect_raises(RuntimeError) do
      clock.schedule(Event(UInt64).new(1_u16, 1_u32, 149_u64, 1_u64))
    end
  end

  it "uses an exclusive advance_to horizon and preserves timestamp order" do
    clock = Clock(UInt64).new(slot_capacity: 4)
    clock.reset(0_u64, 2000_u64, false)
    [1001_u64, 999_u64, 1000_u64].each do |t|
      clock.schedule(Event(UInt64).new(1_u16, 1_u32, t, 1_u64)).should be_true
    end

    times = Array(UInt64).new(3)
    clock.advance_to(1000_u64) do |event|
      times << event.scheduled_time
      nil
    end
    times.should eq([999_u64])

    clock.advance_to(1000_u64) do |_event|
      fail "An unchanged horizon must not dispatch events"
    end

    times.clear
    clock.advance_to(1002_u64) do |event|
      times << event.scheduled_time
      nil
    end
    times.should eq([1000_u64, 1001_u64])
  end

  it "retains all same-time deliveries without assuming tie order" do
    clock = Clock(UInt64).new(slot_capacity: 4)
    clock.reset(0_u64, 10_u64, false)
    [3_u64, 1_u64, 2_u64].each do |p|
      clock.schedule(Event(UInt64).new(1_u16, 1_u32, 2_u64, p)).should be_true
    end

    payloads = Array(UInt64).new(3)
    clock.advance_to(3_u64) do |event|
      payloads << event.payload
      nil
    end
    payloads.sort!.should eq([1_u64, 2_u64, 3_u64])

    clock.advance_to(4_u64) do |_event|
      fail "Same-time delivery dispatched more than once"
    end
  end

  it "handles a level-1 bucket that aliases the current millisecond after wrap" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(1_u64, 1_000_002_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 1_000_000_u64, 1_u64)).should be_true

    clock.tick do |_event|
      fail "Event dispatched during the first tick"
    end
    clock.advance_to(1_000_000_u64) do |_event|
      fail "Event dispatched before its scheduled time"
    end

    dispatched = 0
    clock.tick do |event|
      event.scheduled_time.should eq(1_000_000_u64)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
  end

  it "accepts delay 999999 but rejects delay 1000000" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(0_u64, 1_000_001_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 999_999_u64, 1_u64)).should be_true
    expect_raises(ArgumentError) do
      clock.schedule(Event(UInt64).new(1_u16, 1_u32, 1_000_000_u64, 1_u64))
    end
  end

  it "reports a full level-0 bucket without dropping accepted entries" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(0_u64, 20_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 5_u64, 2_u64)).should be_true
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 5_u64, 3_u64)).should be_false

    payloads = Array(UInt64).new(2)
    clock.advance_to(6_u64) do |event|
      payloads << event.payload
      nil
    end
    payloads.sort!.should eq([1_u64, 2_u64])
  end

  it "reports a full level-1 bucket without corrupting its accepted timestamps" do
    slot_capacity = 2_u32
    clock = Clock(UInt64).new(slot_capacity: slot_capacity)
    level1_capacity = slot_capacity * LEVEL1_SCALE
    clock.reset(0_u64, 2000_u64, false)
    level1_capacity.times { |i| clock.schedule(Event(UInt64).new(1_u16, 1_u32, 1000_u64 + i, 1_u64)).should be_true}
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 1000_u64 + level1_capacity, 1_u64)).should be_false

    times = Array(UInt64).new(level1_capacity)
    clock.advance_to(1000_u64 + LEVEL1_SCALE) do |event|
      times << event.scheduled_time
      nil
    end
    times.each_with_index { |val, i| val.should eq(1000_u64 + i) }
  end

  it "clears both wheel levels on quiescent reset" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(0_u64, 2000_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 5_u64, 1_u64)).should be_true
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 1005_u64, 1_u64)).should be_true
    clock.reset(0_u64, 2000_u64, true)
    clock.advance_to(1010_u64) do |_event|
      fail "Reset retained a previously scheduled event"
    end
  end

  it "reuses emptied capacity after reset and restarts completion state" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(0_u64, 1_u64, false)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 0_u64, 1_u64)).should be_true

    dispatched = 0
    clock.tick do |event|
      event.scheduled_time.should eq(0_u64)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
    clock.completed?.should be_true

    clock.reset(10_u64, 12_u64, true)
    clock.completed?.should be_false
    clock.next_tick.should eq(10_u64)
    clock.schedule(Event(UInt64).new(1_u16, 1_u32, 10_u64, 1_u64)).should be_true

    dispatched = 0
    clock.tick do |event|
      event.scheduled_time.should eq(10_u64)
      dispatched += 1
      nil
    end
    dispatched.should eq(1)
  end

  it "rejects backwards advancement and invalid reset intervals" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    clock.reset(10_u64, 20_u64, false)
    expect_raises(ArgumentError) do
      clock.advance_to(9_u64) do |_event|
        fail "Backwards advancement dispatched an event"
      end
    end
    expect_raises(ArgumentError) { clock.reset(20_u64, 10_u64, false) }
  end

  it "does not strand an accepted event in a concurrent current-tick publication", tags: "stress" do
    clock = Clock(UInt64).new(slot_capacity: 2)
    1000.times do
      clock.reset(0_u64, 3_u64, false)
      gate = Channel(Nil).new
      result = Channel(Bool | Exception).new(1)
      spawn do
        gate.receive
        begin
          result.send(clock.schedule(Event(UInt64).new(1_u16, 1_u32, 0_u64, 1_u64)))
        rescue ex : Exception
          result.send(ex)
        end
      end
      gate.send(nil)

      observed = Array(UInt64).new(1)
      clock.tick do |event|
        observed << event.scheduled_time
        nil
      end

      outcome = select
      when value = result.receive
        value
      when timeout(5.seconds)
        raise "Concurrent clock publication timeout"
      end

      clock.advance_to(2_u64) do |event|
        observed << event.scheduled_time
        nil
      end

      case outcome
      when Bool
        if outcome
          observed.should eq([0_u64])
        else
          raise "An empty capacity-two clock cannot reject for overload"
        end
      when RuntimeError
        observed.should be_empty
      when Exception
        raise outcome
      end
    end
  end
end
