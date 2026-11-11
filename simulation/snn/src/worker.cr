require "./clock"

class Worker(N, P, R)
  getter network : Network(N, P, R)
  getter worker_id : UInt8
  getter node_count : UInt32
  getter weight_count : UInt32
  getter nodes : Slice(N)
  getter weight_values : Slice(Float64)
  getter forward_route_offsets : Slice(UInt32)
  getter forward_routes : Slice(ForwardRoute)
  getter backward_route_offsets : Slice(UInt32)
  getter backward_routes : Slice(BackwardRoute)
  @clock : Clock(P)
  @failed : Bool = false

  def initialize(
    @network : Network(N, P, R),
    @worker_id : UInt8,
    @node_count : UInt32,
    @nodes : Slice(N),
    @weight_values : Slice(Float64),
    @forward_route_offsets : Slice(UInt32),
    @forward_routes : Slice(ForwardRoute),
    @backward_route_offsets : Slice(UInt32),
    @backward_routes : Slice(BackwardRoute),
    slot_capacity : UInt32
  )
    @weight_count = @weight_values.size.to_u32
    @clock = Clock(P).new(slot_capacity: slot_capacity)
    raise ArgumentError.new("Invalid worker ID: #{@worker_id}") if @worker_id.to_u32 >= @network.worker_count.to_u32
    raise ArgumentError.new("Worker node count exceeds UInt16 address capacity.") if @node_count > UInt16::MAX.to_u32 + 1_u32
    raise ArgumentError.new("Node state count #{@nodes.size} does not match node count #{@node_count}") if @nodes.size.to_u32 != @node_count
    validate_route_offsets!(@forward_route_offsets, @forward_routes.size, "Forward.")
    validate_route_offsets!(@backward_route_offsets, @backward_routes.size, "Backward.")
    @forward_routes.each do |route|
      raise ArgumentError.new("Forward route refers to an invalid worker.") if route.target_worker_id.to_u32 >= @network.worker_count.to_u32
    end
    @backward_routes.each do |route|
      raise ArgumentError.new("Backward route refers to an invalid worker.") if route.source_worker_id.to_u32 >= @network.worker_count.to_u32
      raise ArgumentError.new("Backward route refers to an invalid local weight.") if route.worker_local_weight_index >= @weight_count
    end
  end

  def node(worker_local_node_index : UInt16) : N
    nodes[worker_local_node_index]
  end

  def weight_value(worker_local_weight_index : UInt32) : Float64
    weight_values[worker_local_weight_index]
  end

  def set_weight_value(worker_local_weight_index : UInt32, value : Float64) : Nil
    weight_values[worker_local_weight_index] = value
  end

  def add_to_weight_value(worker_local_weight_index : UInt32, delta : Float64) : Nil
    weight_values[worker_local_weight_index] += delta
  end

  def forward_route_range(worker_local_node_index : UInt16) : Range(UInt32, UInt32)
    {% if flag?(:verify_parameters) %}
      validate_node_index!(worker_local_node_index)
    {% end %}
    @forward_route_offsets[worker_local_node_index]...@forward_route_offsets[worker_local_node_index + 1]
  end

  def backward_route_range(worker_local_node_index : UInt16) : Range(UInt32, UInt32)
    {% if flag?(:verify_parameters) %}
      validate_node_index!(worker_local_node_index)
    {% end %}
    @backward_route_offsets[worker_local_node_index]...@backward_route_offsets[worker_local_node_index + 1]
  end

  def each_forward_route(worker_local_node_index : UInt16, & : ForwardRoute -> Nil) : Nil
    forward_route_range(worker_local_node_index).each do |route_index|
      yield @forward_routes[route_index]
    end
    nil
  end

  def each_backward_route(worker_local_node_index : UInt16, & : BackwardRoute, Float64, UInt32 -> Nil) : Nil
    backward_route_range(worker_local_node_index).each do |route_index|
      route = @backward_routes[route_index]
      weight_index = route.worker_local_weight_index
      yield route, @weight_values[weight_index], weight_index
    end
    nil
  end

  def reset(start_time : UInt64, end_time_exclusive : UInt64, clear_buffers : Bool) : Nil
    {% if flag?(:verify_parameters) %}
      raise ArgumentError.new("Exclusive end time time must not precede or equal start time.") if end_time_exclusive <= start_time
    {% end %}
    @clock.reset(start_time, end_time_exclusive, clear_buffers)
    reset_nodes
    @failed = false
    nil
  end

  def reset_nodes : Nil
    nodes.each(&.reset)
  end

  def reset_weight_values(value : Float64 = 0.0) : Nil
    @weight_values.fill(value)
    nil
  end

  def completed? : Bool
    @clock.completed?
  end

  def drained? : Bool
    @clock.drained?
  end

  def next_tick : UInt64
    @clock.next_tick
  end

  def schedule(target_local_index : UInt16, arrival_backward_route_index : UInt32?, target_time : UInt64, payload : P) : Bool
    {% if flag?(:verify_parameters) %}
      validate_node_index!(target_local_index)
      # arrival_backward_route_index can be nil, but inside this block, incoming_index is not.
      if incoming_index = arrival_backward_route_index
        raise IndexError.new("Invalid incoming route index: #{incoming_index}") if incoming_index >= @backward_routes.size.to_u32
        unless incoming_index >= @backward_route_offsets[target_local_index] && incoming_index < @backward_route_offsets[target_local_index + 1]
          raise ArgumentError.new("Incoming route #{incoming_index} does not belong to local node #{target_local_index}")
        end
      end
    {% end %}
    @clock.schedule(Event(P).new(target_local_index, arrival_backward_route_index, target_time, payload))
  end

  def iterate : Symbol
    raise RuntimeError.new("Worker #{@worker_id} requires reset after a failed iteration.") if @failed
    return :break if completed?
    horizon = @network.horizon_next_tick(@worker_id.to_u32)
    return :yield unless horizon > @clock.next_tick
    @clock.advance_to(horizon) do |event|
      local_index = event.target_local_node_index
      process_result = @nodes[local_index].process(event)
      {% if R == Bool %}
        next unless process_result
      {% end %}
      route_index = @forward_route_offsets[local_index]
      route_limit = @forward_route_offsets[local_index + 1]
      next if route_index == route_limit

      latency = @network.layer_latency
      {% if flag?(:verify_parameters) %}
        raise ArgumentError.new("Outgoing event time exceeds UInt64 capacity.") if event.scheduled_time > UInt64::MAX - latency
      {% end %}

      target_time = event.scheduled_time + latency
      payload = unit_payload
      while route_index < route_limit
        route = @forward_routes[route_index]
        peer = @network.workers[route.target_worker_id]
        accepted = peer.schedule(route.target_worker_local_node_index, route.target_backward_route_index, target_time, payload)
        unless accepted
          raise RuntimeError.new("Worker #{route.target_worker_id} can't accept event for #{route.target_worker_local_node_index} at #{target_time}")
        end
        route_index += 1_u32
      end
    end

    @network.record_progress(@worker_id.to_u32, @clock.next_tick)
    :iterated
  rescue ex : Exception
    @failed = true
    raise ex
  end

  private def unit_payload : P
    {% if P == UInt64 %}
      1_u64
    {% elsif P == Float64 %}
      1.0_f64
    {% else %}
      {% raise "Worker unit-payload propagation supports UInt64 or Float64 payloads." %}
    {% end %}
  end

  private def validate_node_index!(local_index : UInt16) : Nil
    raise IndexError.new("Invalid worker-local node index: #{local_index}") if local_index.to_u32 >= @node_count
    nil
  end

  private def validate_route_offsets!(offsets : Slice(UInt32), route_count : Int32, label : String) : Nil
    unless offsets.size == @nodes.size + 1
      raise ArgumentError.new("#{label} offsets must contain node_count + 1 entries.")
    end
    unless offsets[0] == 0_u32 && offsets[offsets.size - 1] == route_count.to_u32
      raise ArgumentError.new("#{label} offsets require zero start and route-count sentinel.")
    end
    previous = 0_u32
    offsets.each do |offset|
      if offset < previous || offset > route_count.to_u32
        raise ArgumentError.new("#{label} offsets must be monotonic and within route bounds.")
      end
      previous = offset
    end
    nil
  end

  def debug_pending : Nil
    @clock.debug_pending("Worker #{@worker_id}")
  end

end
