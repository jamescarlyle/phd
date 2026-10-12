require "./event"

# A four-level hierarchical timing clock with a one-microsecond base tick.
# current_time is always the tick currently being processed by #tick.
class HierarchicalClock
  BITS_0 = 8
  BITS_1 = 8
  BITS_2 = 8
  BITS_3 = 8

  SHIFT_0 = 0
  SHIFT_1 = BITS_0
  SHIFT_2 = BITS_0 + BITS_1
  SHIFT_3 = BITS_0 + BITS_1 + BITS_2

  MASK_0 = (1_u64 << BITS_0) - 1
  MASK_1 = (1_u64 << BITS_1) - 1
  MASK_2 = (1_u64 << BITS_2) - 1
  MASK_3 = (1_u64 << BITS_3) - 1

  TIER_0_RANGE = 1_u64 << SHIFT_1
  TIER_1_RANGE = 1_u64 << SHIFT_2
  TIER_2_RANGE = 1_u64 << SHIFT_3
  WHEEL_CAPACITY = (1_u64 << (SHIFT_3 + BITS_3)) - 1

  getter current_time : UInt64

  @tier1 : Array(Array(Event))
  @tier2 : Array(Array(Event))
  @tier3 : Array(Array(Event))
  @tier4 : Array(Array(Event))

  def initialize(@current_time : UInt64 = 0_u64)
    @tier1 = Array(Array(Event)).new(1 << BITS_0) { Array(Event).new }
    @tier2 = Array(Array(Event)).new(1 << BITS_1) { Array(Event).new }
    @tier3 = Array(Array(Event)).new(1 << BITS_2) { Array(Event).new }
    @tier4 = Array(Array(Event)).new(1 << BITS_3) { Array(Event).new }
  end

  def reset(timestamp : UInt64) : Void
    @current_time = timestamp
  end

  # Schedules an event delay microseconds after current_time.
  # A zero delay is due on the currently processed tick.
  def schedule(target_node_id : UInt32, delay : UInt64, payload : Float64 = 0.0) : Void
    raise RuntimeError.new("Delay exceeds clock capacity") if delay > WHEEL_CAPACITY
    schedule(Event.new(target_node_id, @current_time + delay, payload))
  end

  # Schedules an event for an absolute microsecond timestamp.
  def schedule(event : Event) : Void
    if event.process_at < @current_time
      raise RuntimeError.new("Clock time #{@current_time}: Cannot schedule an event with time #{event.process_at}")
    end
    insert(event)
  end

  # Processes every tick through target_time, exclusively i.e. start <= t < end.
  def advance_to(target_time : UInt64, &block : Event -> Void) : Void
    raise RuntimeError.new("Cannot move backwards: target=#{target_time}, current=#{@current_time}") if target_time < @current_time
    while @current_time < target_time
      tick { |event| block.call(event) }
    end
  end

  # Processes events due at current_time, then advances current_time by one tick.
  def tick(&block : Event -> Void) : Void
    run_current_slot { |event| block.call(event) }
    advance_one_tick
  end

  private def insert(event : Event) : Void
    delay = event.process_at - @current_time
    if delay < TIER_0_RANGE
      @tier1[(event.process_at & MASK_0).to_i] << event
    elsif delay < TIER_1_RANGE
      @tier2[((event.process_at >> SHIFT_1) & MASK_1).to_i] << event
    elsif delay < TIER_2_RANGE
      @tier3[((event.process_at >> SHIFT_2) & MASK_2).to_i] << event
    else
      @tier4[((event.process_at >> SHIFT_3) & MASK_3).to_i] << event
    end
  end

  private def run_current_slot(&block : Event -> Void) : Void
    slot = (@current_time & MASK_0).to_i
    bucket = @tier1[slot]
    return if bucket.empty?

    events = bucket.dup
    bucket.clear

    events.each do |event|
      if event.process_at == @current_time
        block.call(event)
      elsif event.process_at > @current_time
        insert(event)
      else
        raise "Expired event encountered at #{event.process_at}; current time is #{@current_time}"
      end
    end
  end

  private def advance_one_tick : Void
    @current_time += 1
    if (@current_time & MASK_0) == 0
      cascade_tier2
      if (@current_time & ((1_u64 << SHIFT_2) - 1)) == 0
        cascade_tier3
        if (@current_time & ((1_u64 << SHIFT_3) - 1)) == 0
          cascade_tier4
        end
      end
    end
  end

  private def cascade_tier2 : Void
    cascade(@tier2[((@current_time >> SHIFT_1) & MASK_1).to_i])
  end

  private def cascade_tier3 : Void
    cascade(@tier3[((@current_time >> SHIFT_2) & MASK_2).to_i])
  end

  private def cascade_tier4 : Void
    cascade(@tier4[((@current_time >> SHIFT_3) & MASK_3).to_i])
  end

  private def cascade(bucket : Array(Event)) : Void
    return if bucket.empty?
    events = bucket.dup
    bucket.clear
    events.each { |event| insert(event) }
  end
end
