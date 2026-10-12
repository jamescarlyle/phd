require "./event"

class CrossWorkerQueue
  def initialize(initial_capacity : Int32 = 4096)
    @buffer_a = Array(Event).new(initial_capacity)
    @buffer_b = Array(Event).new(initial_capacity)
    @mutex = Mutex.new
  end

  def push(event : Event) : Void
    @mutex.synchronize do
      @buffer_a << event
    end
  end

  def drain_into(clock : HierarchicalClock) : Void
    # Fast path: check if empty before acquiring the lock.
    return if @buffer_a.empty?
    # Ensure our local drain buffer is completely empty.
    @buffer_b.clear

    @mutex.synchronize do
      # Swap pointers: @buffer_b gets all pending events,
      # and @buffer_a receives the clean, pre-allocated backing array
      @buffer_a, @buffer_b = @buffer_b, @buffer_a
      @buffer_a.clear
    end

    # Process from @buffer_b.
    #  No other thread or fiber touches @buffer_b while this worker runs.
    @buffer_b.each do |event|
      clock.schedule(event)
    end

  end

end
