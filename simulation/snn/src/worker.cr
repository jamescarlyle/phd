require "./clock"

class Worker(N, P, R)
  @clock = Clock(P).new
  @nodes = Array(N).new
  getter worker_id
  getter nodes : Array(N)

  def initialize(@worker_id : UInt32, @network : Network(N, P, R), num_layers : UInt32)
    @layer_start = Array(UInt32).new(num_layers, 0u32)
    @layer_count = Array(UInt32).new(num_layers, 0u32)
  end

  def add_node(node_id : UInt32)
    node = N.new(node_id)
    layer_idx = @network.layer_idx(node_id)
    @layer_start[layer_idx] = @nodes.size.to_u32 if @layer_count[layer_idx] == 0
    @nodes << node
    @layer_count[layer_idx] += 1
  end

  def nodes_in_layer(layer_idx : UInt32) : Array(N)
    count = @layer_count[layer_idx]
    return [] of N if count == 0
    start = @layer_start[layer_idx]
    @nodes[start, count]
  end

  def propagate(target_layer_idx : UInt32, target_time : UInt64, state : P)
    start = @layer_start[target_layer_idx]
    count = @layer_count[target_layer_idx]
    count.times do |offset|
      schedule(start + offset, target_time, state)
    end
  end

  def iterate : Symbol
    return :break if completed?
    horizon = @network.horizon_next_tick(@worker_id)
    return :yield unless horizon > @clock.next_tick

    events = @clock.advance_to(horizon)
    events.each do |event|
      process_node = @nodes[event.target_local_node_idx]
      process_result = process_node.process(event)
      @network.propagate(process_node, event.scheduled_time, process_result)
    end
    @network.record_progress(@worker_id, @clock.next_tick)
    :iterated
  end

  def completed? : Bool
    @clock.completed?
  end

  def reset(start_time : UInt64, last_process_time : UInt64)
    @clock.reset(start_time, last_process_time)
  end

  def next_tick : UInt64
    @clock.next_tick
  end

  def schedule(target_local_idx : UInt32, target_time : UInt64, payload : P) : Void
    @clock.schedule(Event(P).new(target_local_idx, target_time, payload))
  end

end
