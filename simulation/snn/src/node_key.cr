require "./constant"

struct NodeKey

  getter worker_id : UInt8
  getter worker_local_node_index : UInt16

  def initialize(@worker_id : UInt8, @worker_local_node_index : UInt16)
    if @worker_id >= MAX_WORKERS
      raise ArgumentError.new(
        "Worker ID #{@worker_id} must be less than #{MAX_WORKERS}"
      )
    end
  end

  def_equals_and_hash @worker_id, @worker_local_node_index

  def packed_value : UInt32
    (worker_id.to_u32 << LOCAL_NODE_INDEX_BITS) |
      worker_local_node_index.to_u32
  end

  def self.from_packed_value(packed_value : UInt32) : NodeKey
    worker_part = packed_value >> LOCAL_NODE_INDEX_BITS

    if worker_part >= MAX_WORKERS.to_u32
      raise ArgumentError.new("Invalid packed NodeKey: #{packed_value}")
    end

    local_part = (packed_value & LOCAL_NODE_INDEX_MASK).to_u16!
    NodeKey.new(worker_part.to_u8!, local_part)
  end
end
