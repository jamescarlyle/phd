require "./event"

# struct CrossWorkerMessage
#   property target_node : UInt32
#   property delay : UInt64
#   property payload : Float64

#   def initialize(@target_node = 0_u32, @delay = 0_u64, @payload = 0.0)
#   end
# end

class CrossWorkerQueue
  def initialize
    @buffer = Array(Event).new(initial_capacity: 4096)
    @drain_buffer = Array(Event).new(initial_capacity: 4096)
    @mutex = Mutex.new
  end

  def push(event : Event) : Void
    @mutex.synchronize do
      @buffer << event
    end
  end

  def drain_into(wheel : HierarchicalWheel) : Void
    messages = @mutex.synchronize do
      events = @buffer
      @buffer = @drain_buffer
      @drain_buffer = events
      @buffer.clear
      events
    end

    messages.each do |event|
      wheel.schedule(event)
    end
  end
end
