require "./node_key"

struct ForwardRoute
  getter target_worker_id : UInt8
  getter target_worker_local_node_index : UInt16

  def initialize(
    @target_worker_id : UInt8,
    @target_worker_local_node_index : UInt16
  )
  end

  def target_key : NodeKey
    NodeKey.new(
      target_worker_id,
      target_worker_local_node_index
    )
  end
end

struct BackwardRoute
  getter source_worker_id : UInt8
  getter source_worker_local_node_index : UInt16
  getter worker_local_weight_index : UInt32

  def initialize(
    @source_worker_id : UInt8,
    @source_worker_local_node_index : UInt16,
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
