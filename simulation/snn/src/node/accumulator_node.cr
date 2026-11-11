require "./base_node"

class AccumulatorNode < Node(UInt64, UInt64)
  getter accumulation : UInt64
  getter processed_count : UInt64 = 0_u64

  def initialize(@accumulation : UInt64 = 0_u64)
    super()
  end

  def process(event : Event(UInt64)) : UInt64
    @processed_count += 1_u64
    @accumulation += event.payload
    @accumulation
  end

  def reset : Nil
    @accumulation = 0
    @processed_count = 0
  end


end
