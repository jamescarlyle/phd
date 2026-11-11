require "./node_key"

struct ForwardRoute
  getter target_worker_id : UInt8
  getter target_worker_local_node_index : UInt16
  getter target_backward_route_index : UInt32

  def initialize(
    @target_worker_id : UInt8,
    @target_worker_local_node_index : UInt16,
    @target_backward_route_index : UInt32
  )
  end

  def target_key : NodeKey
    NodeKey.new(
      target_worker_id,
      target_worker_local_node_index
    )
  end
end

# | Field                          | Meaning                                                                 |
# | ------------------------------ | ----------------------------------------------------------------------- |
# | source_worker_id               | Worker owning the source node and matching outgoing route               |
# | source_worker_local_node_index | Source node's index in that worker's nodes slice                        |
# | source_forward_route_index     | Matching route's index in the source worker's flat forward_routes slice |
# | worker_local_weight_index      | Weight's index in the destination worker's weight_values slice          |

struct BackwardRoute
  getter source_worker_id : UInt8
  getter source_worker_local_node_index : UInt16
  getter source_forward_route_index : UInt32
  getter worker_local_weight_index : UInt32

  def initialize(
    @source_worker_id : UInt8,
    @source_worker_local_node_index : UInt16,
    @source_forward_route_index : UInt32,
    @worker_local_weight_index : UInt32
  )
  end

  def source_key : NodeKey
    NodeKey.new(
      source_worker_id,
      source_worker_local_node_index
    )
  end
end

struct LateralRoute
  getter target_worker_id : UInt8
  getter target_worker_local_node_index : UInt16

  def initialize(
    @target_worker_id : UInt8,
    @target_worker_local_node_index : UInt16
  )
  end
end
