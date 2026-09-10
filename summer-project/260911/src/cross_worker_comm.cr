struct CrossWorkerMessage
  property target_node : UInt32
  property delay : UInt64
  property payload : Float64

  def initialize(@target_node = 0_u32, @delay = 0_u64, @payload = 0.0)
  end
end

class CrossWorkerQueue
  def initialize
    @buffer = Array(CrossWorkerMessage).new(initial_capacity: 4096)
    @drain_buffer = Array(CrossWorkerMessage).new(initial_capacity: 4096)
    @mutex = Mutex.new
  end

  def push(target_node : UInt32, delay : UInt64, payload : Float64) : Void
    @mutex.synchronize do
      @buffer << CrossWorkerMessage.new(target_node, delay, payload)
    end
  end

  def drain_into(wheel : HierarchicalWheel) : Void
    messages = @mutex.synchronize do
      msgs = @buffer
      @buffer = @drain_buffer
      @drain_buffer = msgs
      @buffer.clear
      msgs
    end

    messages.each do |msg|
      wheel.schedule(msg.target_node, msg.delay, msg.payload)
    end
  end
end
