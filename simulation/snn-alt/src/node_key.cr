struct NodeKey
  getter worker_id : UInt8
  getter worker_local_node_index : UInt16

  def initialize(@worker_id : UInt8, @worker_local_node_index : UInt16)
  end

  def packed_value : UInt32
    worker_id.to_u32 << MAX_NODES_PER_LAYER_SHIFT |
      worker_local_node_index.to_u32
  end

  def self.from_packed_value(packed_value : UInt32) : NodeKey
    worker_id =
      ((packed_value >> MAX_NODES_PER_LAYER_SHIFT) & MAX_WORKERS_MASK).to_u8!

    worker_local_node_index =
      (packed_value & MAX_NODES_PER_LAYER_MASK).to_u16!

    NodeKey.new(worker_id, worker_local_node_index)
  end
end

struct NodeAllocation
  getter worker_id : UInt8
  getter worker_local_node_index : UInt16
  getter global_node_index : UInt32

  def initialize(
    @worker_id : UInt8,
    @worker_local_node_index : UInt16,
    @global_node_index : UInt32
  )
  end

  def key : NodeKey
    NodeKey.new(worker_id, worker_local_node_index)
  end
end
