struct Event(P)
  getter source_global_node_index : UInt32
  getter target_local_node_index : UInt16
  getter scheduled_time : UInt64
  getter payload : P

  def initialize(@source_global_node_index : UInt32, @target_local_node_index : UInt16,
    @scheduled_time : UInt64, @payload : P)
  end
end
