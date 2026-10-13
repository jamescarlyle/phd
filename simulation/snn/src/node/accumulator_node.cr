require "./base_node"

class AccumulatorNode < Node(UInt64, UInt64)
  getter accumulation : UInt64
  getter processed_count : UInt64 = 0_u64

  def initialize(node_id : UInt32, @accumulation : UInt64 = 0_u64)
    super(node_id)
  end

  def process(event : Event(UInt64)) : UInt64
    @processed_count += 1_u64
    @accumulation += event.payload
    @accumulation
  end
end
