struct Event(P)
  getter target_local_node_idx : UInt32
  getter scheduled_time : UInt64
  getter payload : P

  def initialize(@target_local_node_idx : UInt32, @scheduled_time : UInt64, @payload : P)
  end
end
