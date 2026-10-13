require "./node/*"

# These compile-time flags are now deprecated. N,P,R types are used throughout.

{% if flag?(:node_lif) %}
  alias ActiveNode = LIFNode
  alias ActivePayload = Float64
  alias ActiveReturn = Bool
{% else %}
  alias ActiveNode = AccumulatorNode
  alias ActivePayload = UInt64
  alias ActiveReturn = UInt64
{% end %}
