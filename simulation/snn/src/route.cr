WEIGHT_MIN = 0.01
WEIGHT_MAX = 0.25

struct TargetRoute
  getter target_worker_id
  getter target_local_node_idx

  def initialize(@target_worker_id : UInt32, @target_local_node_idx : UInt32)
  end
end

struct SourceRoute
  getter source_worker_id
  getter source_local_node_idx
  property weight
  property eligibility

  def initialize(@source_worker_id : UInt32, @source_local_node_idx : UInt32,
    @weight : Float64 = Random.rand(WEIGHT_MIN..WEIGHT_MAX), @eligibility : Float64 = 0.0)
  end
end

# struct OutgoingRoute
#   synapse_id : UInt32
#   dst_worker : UInt16
#   dst_local_idx : UInt32
#   delay_us : UInt32
# end
