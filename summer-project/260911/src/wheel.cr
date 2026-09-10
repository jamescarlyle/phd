struct Event
  getter target_node : UInt32
  getter expires_at : UInt64
  getter payload : Float64

  def initialize(@target_node : UInt32 = 0_u32, @expires_at : UInt64 = 0_u64, @payload : Float64 = 0.0)
  end
end

# A four-level hierarchical timing wheel with a one-microsecond base tick.
# current_time is always the tick currently being processed by #tick.
class HierarchicalWheel
  BITS_1 = 8
  BITS_2 = 8
  BITS_3 = 8
  BITS_4 = 8

  SHIFT_1 = 0
  SHIFT_2 = BITS_1
  SHIFT_3 = BITS_1 + BITS_2
  SHIFT_4 = BITS_1 + BITS_2 + BITS_3

  MASK_1 = (1_u64 << BITS_1) - 1
  MASK_2 = (1_u64 << BITS_2) - 1
  MASK_3 = (1_u64 << BITS_3) - 1
  MASK_4 = (1_u64 << BITS_4) - 1

  TIER_1_RANGE = 1_u64 << SHIFT_2
  TIER_2_RANGE = 1_u64 << SHIFT_3
  TIER_3_RANGE = 1_u64 << SHIFT_4
  MAX_DELAY = (1_u64 << (SHIFT_4 + BITS_4)) - 1

  getter current_time : UInt64

  @tier1 : Array(Array(Event))
  @tier2 : Array(Array(Event))
  @tier3 : Array(Array(Event))
  @tier4 : Array(Array(Event))

  def initialize(@current_time : UInt64 = 0_u64)
    @tier1 = Array(Array(Event)).new(1 << BITS_1) { Array(Event).new }
    @tier2 = Array(Array(Event)).new(1 << BITS_2) { Array(Event).new }
    @tier3 = Array(Array(Event)).new(1 << BITS_3) { Array(Event).new }
    @tier4 = Array(Array(Event)).new(1 << BITS_4) { Array(Event).new }
  end

  # Schedules an event delay microseconds after current_time.
  # A zero delay is due on the currently processed tick.
  def schedule(target : UInt32, delay : UInt64, payload : Float64 = 0.0) : Void
    raise RuntimeError.new("Delay exceeds wheel capacity") if delay > MAX_DELAY
    schedule_at(target, @current_time + delay, payload)
  end

  # Schedules an event for an absolute microsecond timestamp.
  def schedule_at(target : UInt32, expires_at : UInt64, payload : Float64 = 0.0) : Void
    raise RuntimeError.new("Cannot schedule an event in the past") if expires_at < @current_time
    insert(Event.new(target, expires_at, payload))
  end

  # Processes events due at current_time, then advances current_time by one tick.
  def tick(&block : Event -> Void) : Void
    run_current_slot { |event| block.call(event) }
    advance_one_tick
  end

  # Processes every tick through target_time, inclusively.
  # After returning, current_time is target_time + 1.
  def advance_to(target_time : UInt64, &block : Event -> Void) : Void
    raise RuntimeError.new("Cannot move backwards") if target_time < @current_time
    while @current_time <= target_time
      tick { |event| block.call(event) }
    end
  end

  private def insert(event : Event) : Void
    delay = event.expires_at - @current_time
    if delay < TIER_1_RANGE
      @tier1[(event.expires_at & MASK_1).to_i] << event
    elsif delay < TIER_2_RANGE
      @tier2[((event.expires_at >> SHIFT_2) & MASK_2).to_i] << event
    elsif delay < TIER_3_RANGE
      @tier3[((event.expires_at >> SHIFT_3) & MASK_3).to_i] << event
    else
      @tier4[((event.expires_at >> SHIFT_4) & MASK_4).to_i] << event
    end
  end

  private def run_current_slot(&block : Event -> Void) : Void
    slot = (@current_time & MASK_1).to_i
    bucket = @tier1[slot]
    return if bucket.empty?

    events = bucket.dup
    bucket.clear

    events.each do |event|
      if event.expires_at == @current_time
        block.call(event)
      elsif event.expires_at > @current_time
        insert(event)
      else
        raise "Expired event encountered at #{event.expires_at}; current time is #{@current_time}"
      end
    end
  end

  private def advance_one_tick : Void
    @current_time += 1
    if (@current_time & MASK_1) == 0
      cascade_tier2
      if (@current_time & ((1_u64 << SHIFT_3) - 1)) == 0
        cascade_tier3
        if (@current_time & ((1_u64 << SHIFT_4) - 1)) == 0
          cascade_tier4
        end
      end
    end
  end

  private def cascade_tier2 : Void
    cascade(@tier2[((@current_time >> SHIFT_2) & MASK_2).to_i])
  end

  private def cascade_tier3 : Void
    cascade(@tier3[((@current_time >> SHIFT_3) & MASK_3).to_i])
  end

  private def cascade_tier4 : Void
    cascade(@tier4[((@current_time >> SHIFT_4) & MASK_4).to_i])
  end

  private def cascade(bucket : Array(Event)) : Void
    return if bucket.empty?
    events = bucket.dup
    bucket.clear
    events.each { |event| insert(event) }
  end
end
