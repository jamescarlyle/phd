require "./constant"
require "./buffer"

class Clock(P)

  MICROSECONDS_PER_MS     =     1_000_u64
  MS_PER_SECOND           =     1_000_u64
  MICROSECONDS_PER_SECOND = 1_000_000_u64

  @next_tick = Atomic(UInt64).new(0)
  @last_process_time = Atomic(UInt64).new(0)
  getter slot_capacity : Int32
  getter level_0 : Array(Buffer(P))
  getter level_1 : Array(Buffer(P))

  def initialize(@slot_capacity : Int32 = 64)
    @level_0 = Array(Buffer(P)).new(MICROSECONDS_PER_MS.to_i) do
      Buffer(P).new(@slot_capacity)
    end
    @level_1 = Array(Buffer(P)).new(MS_PER_SECOND.to_i) do
      Buffer(P).new(@slot_capacity)
    end
  end

  def next_tick : UInt64
    @next_tick.get
  end

  def completed? : Bool
    @next_tick.get >= @last_process_time.get
  end

  def reset(start_time : UInt64, last_process_time : UInt64) : Void
    @next_tick.set(start_time)
    @last_process_time.set(last_process_time)
  end

  def schedule(event : Event(P)) : Bool
    next_tick = @next_tick.get
    unless event.scheduled_time >= next_tick
      raise RuntimeError.new("Clock time #{next_tick}: Cannot schedule an event with time #{event.scheduled_time}")
    end

    if event.scheduled_time < next_tick
      target_slot = (next_tick % MICROSECONDS_PER_MS).to_i
      return @level_0[target_slot].push(event)
    end

    delay = event.scheduled_time - next_tick
    if delay >= MICROSECONDS_PER_SECOND
      raise ArgumentError.new("Event scheduled beyond 1-second capacity (#{delay} us)")
    end

    current_ms = next_tick // MICROSECONDS_PER_MS
    target_ms = event.scheduled_time // MICROSECONDS_PER_MS

    if current_ms == target_ms
      slot = (event.scheduled_time % MICROSECONDS_PER_MS).to_i
      @level_0[slot].push(event)
    else
      slot = (target_ms % MS_PER_SECOND).to_i
      @level_1[slot].push(event)
    end
  end

  def tick : Array(Event(P))
    current = @next_tick.get
    us_slot = (current % MICROSECONDS_PER_MS).to_i
    ms_slot = ((current // MICROSECONDS_PER_MS) % MS_PER_SECOND).to_i

    dispatched = Array(Event(P)).new

    while cascading_event = @level_1[ms_slot].pop
      target_us = (cascading_event.scheduled_time % MICROSECONDS_PER_MS).to_i
      if target_us <= us_slot
        dispatched << cascading_event
      else
        @level_0[target_us].push(cascading_event)
      end
    end

    while event = @level_0[us_slot].pop
      dispatched << event
    end

    @next_tick.set(current + 1_u64)
    dispatched
  end

  def advance_to(next_tick : UInt64) : Array(Event(P))
    steps = next_tick - @next_tick.get
    events = Array(Event(P)).new
    steps.times do
      batch = tick
      events.concat(batch) unless batch.empty?
    end
    events
  end
end
