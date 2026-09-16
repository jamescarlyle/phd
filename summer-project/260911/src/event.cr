struct Event
  getter target_node : UInt32
  getter process_at : UInt64
  getter payload : Float64

  def initialize(@target_node : UInt32 = 0_u32, @process_at : UInt64 = 0_u64, @payload : Float64 = 0.0)
  end
end
