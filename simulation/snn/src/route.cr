WEIGHT_MIN = 0.01
WEIGHT_MAX = 0.25

struct Route
  getter target_worker_id
  getter target_local_node_idx
  property weight

  def initialize(@target_worker_id : UInt32, @target_local_node_idx : UInt32,
    @weight : Float64 = Random.rand(WEIGHT_MIN..WEIGHT_MAX))
  end
end
