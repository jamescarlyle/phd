require "./clock"

class Worker(N, P, R)
  @network : Network(N, P, R)
  @clock = Clock(P).new
  getter worker_id : UInt8
  getter node_count : UInt32
  getter weight_count : UInt32
  getter network : Network(N, P, R)

  getter nodes : Slice(N)
  getter weight_values : Slice(Float64)

  getter forward_route_offsets : Slice(UInt32)
  getter forward_routes : Slice(ForwardRoute)

  getter backward_route_offsets : Slice(UInt32)
  getter backward_routes : Slice(BackwardRoute)

  def initialize(
    @network : Network(N, P, R),
    @worker_id : UInt8,
    @node_count : UInt32,
    @nodes : Slice(N),
    @weight_values : Slice(Float64),
    @forward_route_offsets : Slice(UInt32),
    @forward_routes : Slice(ForwardRoute),
    @backward_route_offsets : Slice(UInt32),
    @backward_routes : Slice(BackwardRoute)
  )
    @weight_count = weight_values.size.to_u32

    if nodes.size != node_count
      raise ArgumentError.new(
        "Node state count #{nodes.size} does not match node count #{node_count}"
      )
    end
  end

  def node(worker_local_node_index : UInt16) : N
    nodes[worker_local_node_index]
  end

  def weight_value(worker_local_weight_index : UInt32) : Float64
    weight_values[worker_local_weight_index]
  end

  def set_weight_value(
    worker_local_weight_index : UInt32,
    value : Float64
  ) : Nil
    weight_values[worker_local_weight_index] = value
  end

  def add_to_weight_value(
    worker_local_weight_index : UInt32,
    delta : Float64
  ) : Nil
    weight_values[worker_local_weight_index] += delta
  end

  def forward_route_range(global_node_index : UInt32) : Range(UInt32, UInt32)
    forward_route_offsets[global_node_index]...forward_route_offsets[global_node_index + 1]
  end

  def backward_route_range(global_node_index : UInt32) : Range(UInt32, UInt32)
    backward_route_offsets[global_node_index]...backward_route_offsets[global_node_index + 1]
  end

  def each_forward_route(
    global_node_index : UInt32,
    & : ForwardRoute -> Nil
  ) : Nil
    forward_route_range(global_node_index).each do |route_index|
      yield forward_routes[route_index]
    end
  end

  def each_backward_route(
    global_node_index : UInt32,
    & : BackwardRoute, Float64, UInt32 -> Nil
  ) : Nil
    backward_route_range(global_node_index).each do |route_index|
      route = backward_routes[route_index]

      yield(
        route,
        weight_values[route.worker_local_weight_index],
        route.worker_local_weight_index
      )
    end
  end

  def reset(start_time : UInt64, last_process_time : UInt64) : Nil
    @clock.reset(start_time, last_process_time)
    reset_nodes
    reset_weight_values
  end

  def reset_nodes : Nil
    nodes.each(&.reset)
  end

  def reset_weight_values : Nil
    weight_values.each_with_index do |_, weight_index|
      weight_values[weight_index] = 0.0
    end
  end

  def iterate : Symbol
    return :break if completed?
    horizon = @network.horizon_next_tick(@worker_id)
    return :yield unless horizon > @clock.next_tick

    events = @clock.advance_to(horizon)
    events.each do |event|
      local_index = event.target_local_node_index
      process_node = @nodes[local_index]
      process_result = process_node.process(event)

      allocation = @network.node_allocations.find do |candidate|
        candidate.worker_id == @worker_id &&
          candidate.worker_local_node_index == local_index
      end

      raise "Missing allocation for processed node" unless allocation

      @network.propagate(
        allocation.global_node_index,
        event.scheduled_time,
        process_result
      )
    end
    # events.each do |event|
    #   process_node = @nodes[event.target_local_node_index]
    #   process_result = process_node.process(event)
    #   @network.propagate(event.source_global_node_index, event.scheduled_time, process_result)
    # end
    @network.record_progress(@worker_id, @clock.next_tick)
    :iterated
  end

  def completed? : Bool
    @clock.completed?
  end

  def next_tick : UInt64
    @clock.next_tick
  end

  def schedule(source_global_node_index : UInt32, target_local_idx : UInt16, target_time : UInt64, payload : P) : Void
    @clock.schedule(Event(P).new(source_global_node_index, target_local_idx, target_time, payload))
  end

end
