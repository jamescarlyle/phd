class Router
  def initialize(
    @workers : Array(Worker),
    @layer_bounds : Array(LayerBounds),
    @worker_count : Int32
  )
  end

  def dispatch(from_node : Node, state : Float64, current_worker_id : Int32) : Nil
    next_layer_idx = from_node.layer_index + 1
    return if next_layer_idx >= @layer_bounds.size

    bounds = @layer_bounds[next_layer_idx]
    target_node_id = bounds.start_id

    while target_node_id <= bounds.end_id
      target_worker_id = (target_node_id % @worker_count).to_i
      delay = 1_u64

      if target_worker_id == current_worker_id
        # Local event: schedule directly on this worker's wheel.
        @workers[current_worker_id].wheel.schedule(target_node_id, delay, state)
      else
        # Cross-worker: use the dedicated queue from current_worker_id -> target_worker_id.
        @workers[target_worker_id].enqueue(current_worker_id, target_node_id, delay, state)
      end

      target_node_id += 1_u32
    end
  end
end
