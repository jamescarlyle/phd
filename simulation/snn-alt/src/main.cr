require "./constant"
require "./network"

network = Network(AccumulatorNode, UInt64, UInt64).new(LAYER_SIZES, MAX_WORKERS)
print network
puts
