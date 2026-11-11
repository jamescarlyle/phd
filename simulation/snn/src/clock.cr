require "./constant"
require "./buffer"

class Clock(P)

  MICROSECONDS_PER_MS     =     1_000_u64
  MS_PER_SECOND           =     1_000_u64
  MICROSECONDS_PER_SECOND = 1_000_000_u64

  @next_tick = Atomic(UInt64).new(0)
  @end_time_exclusive = Atomic(UInt64).new(0)
  getter slot_capacity : UInt32
  getter level_0 : Array(Buffer(P))
  getter level_1 : Array(Buffer(P))

  def initialize(@slot_capacity : UInt32)
    @level_0 = Array(Buffer(P)).new(MICROSECONDS_PER_MS.to_i) do
      Buffer(P).new(@slot_capacity)
    end
    @level_1 = Array(Buffer(P)).new(MS_PER_SECOND.to_i) do
      Buffer(P).new(@slot_capacity * LEVEL1_SCALE)
    end
  end

  def next_tick : UInt64
    @next_tick.get
  end

  def completed? : Bool
    @next_tick.get >= @end_time_exclusive.get
  end

  def drained? : Bool
    @level_0.all?(&.drained?) && @level_1.all?(&.drained?)
  end

  def reset(start_time : UInt64, end_time_exclusive : UInt64, clear_buffers : Bool) : Void
    {% if flag?(:verify_parameters) %}
      raise ArgumentError.new("Cannot set exclusive end time before or equal to the start time") if end_time_exclusive <= start_time
    {% end %}
    @next_tick.set(start_time)
    @end_time_exclusive.set(end_time_exclusive)
    if clear_buffers
      @level_0.each(&.clear)
      @level_1.each(&.clear)
    end
  end

  def schedule(event : Event(P)) : Bool
    next_tick = @next_tick.get
    {% if flag?(:verify_parameters) %}
      end_time_exclusive = @end_time_exclusive.get
      if event.scheduled_time >= end_time_exclusive
        raise RuntimeError.new("Event outside simulation interval: scheduled_time=#{event.scheduled_time}, next_tick=#{next_tick}, end_time_exclusive=#{end_time_exclusive}")
      end
      if event.scheduled_time < next_tick
        raise RuntimeError.new("Clock time #{next_tick}: Cannot schedule an event with time #{event.scheduled_time}")
      end
    {% end %}
    if event.scheduled_time < next_tick
      target_slot = (next_tick % MICROSECONDS_PER_MS).to_i
      return @level_0[target_slot].push(event)
    end

    delay = event.scheduled_time - next_tick
    {% if flag?(:verify_parameters) %}
      raise ArgumentError.new("Event scheduled beyond 1-second capacity (#{delay} us)") if delay >= MICROSECONDS_PER_SECOND
    {% end %}
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

  def tick(& : Event(P) -> Nil) : Nil
    current = @next_tick.get
    current_ms = current // MICROSECONDS_PER_MS
    us_slot = (current % MICROSECONDS_PER_MS).to_i

    if us_slot == 0
      ms_slot = (current_ms % MS_PER_SECOND).to_i

      while event = @level_1[ms_slot].pop
        target_us = (event.scheduled_time % MICROSECONDS_PER_MS).to_i
        {% if flag?(:verify_parameters) %}
          event_ms = event.scheduled_time // MICROSECONDS_PER_MS
          unless event_ms == current_ms
            raise RuntimeError.new("Invalid level-1 event epoch")
          end
        {% end %}
        unless @level_0[target_us].push(event)
          raise RuntimeError.new("Level-0 bucket full during cascade")
        end
      end
    end

    while event = @level_0[us_slot].pop
      {% if flag?(:verify_parameters) %}
        unless event.scheduled_time == current
          raise RuntimeError.new("Invalid level-0 event timestamp")
        end
      {% end %}
      yield event
    end

    @next_tick.set(current + 1_u64)
    nil
  end

  def advance_to(target : UInt64, & : Event(P) -> Nil) : Nil
    {% if flag?(:verify_parameters) %}
      if target < @next_tick.get
        raise ArgumentError.new("Cannot advance clock backwards")
      end
    {% end %}
    while @next_tick.get < target
      tick do |event|
        yield event
      end
    end
    nil
  end

  def debug_pending(label : String) : Nil
    puts "#{label}: next_tick=#{@next_tick.get}, end_time_exclusive=#{@end_time_exclusive.get}"
    @level_0.each_with_index do |buffer, slot|
      buffer.debug_pending("#{label} L0[#{slot}]")
    end
    @level_1.each_with_index do |buffer, slot|
      buffer.debug_pending("#{label} L1[#{slot}]")
    end
    nil
  end
end
