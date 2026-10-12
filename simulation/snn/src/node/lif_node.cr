require "./base_node"

V_THRESHOLD = 1.0           # Threshold voltage
V_REST = 0.0                # Resting voltage
V_RESET = -1.0              # Reset voltage
TAU_US = 10_000.0           # Time constant

class LIFNode < Node(Float64, Bool)
  alias ReturnType = Bool
  getter potential : Float64

  def initialize(node_id : UInt32, @potential : Float64 = 0.0_f64, @last_update_time : UInt64 = 0)
    super(node_id)
  end

  def process(event : Event(Float64)) : Bool
    return false unless event.scheduled_time >= @last_update_time
    dt = event.scheduled_time - @last_update_time
    @potential *= Math.exp(-dt.to_f / TAU_US)
    @potential += event.payload
    @last_update_time = event.scheduled_time
    return false unless @potential > V_THRESHOLD
    @potential = V_RESET
    true
  end
end
