struct Event(P)
  getter target_local_node_index : UInt16
  getter arrival_backward_route_index : UInt32?
  getter scheduled_time : UInt64
  getter payload : P

  def initialize(
    @target_local_node_index : UInt16,
    @arrival_backward_route_index : UInt32?,
    @scheduled_time : UInt64,
    @payload : P
    )
  end
end
