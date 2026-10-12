require "./base_node"

class AccumulatorNode(P) < Node(P, P)
  getter accumulation : P
  getter processed_count : UInt64 = 0_u64

  def initialize(node_id : UInt32, @accumulation : P = P.zero)
    super(node_id)
  end

  def process(event : Event(P)) : P
    @processed_count += 1_u64
    @accumulation += event.payload
    @accumulation
  end
end
