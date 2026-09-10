class Node
  getter id : UInt32
  getter layer_index : Int32
  property processed_count : UInt64 = 0_u64
  property state_accumulator : Float64 = 0.0

  def initialize(@id : UInt32, @layer_index : Int32)
  end

  def process(payload : Float64) : Float64
    @processed_count += 1
    @state_accumulator = (@state_accumulator * 0.95) + (payload * 0.05)
    @state_accumulator
  end
end
