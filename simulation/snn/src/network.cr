require "./constant"
require "./sync_manager"
require "./node/*"
require "./worker"
require "./route"

class Network(N, P, R)
  property? training : Bool
  getter workers : Array(Worker(N, P, R))
  getter sync_mgr
  getter layer_latency
  @start_channel : Channel(Nil) = Channel(Nil).new
  @done_channel : Channel(Nil) = Channel(Nil).new

  def initialize(@layer_sizes : Array(UInt32), @worker_count : UInt32, @layer_latency : UInt64 = LAYER_LATENCY,
                @max_drift : UInt64 = MAX_DRIFT, @training = false)
    @sync_mgr = SyncManager.new(@worker_count, @layer_latency, @max_drift)
    @workers = Array(Worker(N, P, R)).new(@worker_count)
    @worker_layer_starts = Array(UInt32).new(MAX_WORKERS.to_i * @layer_sizes.size, 0u32)
    @layer_count = @layer_sizes.size
    build_worker_layer_starts
    build_workers
    build_nodes
    build_routes
    start_workers
  end

  private def start_workers : Void
    @workers.each do |worker|
      spawn(name: "worker #{worker.worker_id}") do
        loop do
          @start_channel.receive
          loop do
            result = worker.iterate
            case result
            when :yield then Fiber.yield
            when :break then break
            end
          end
          @done_channel.send(nil)
        end
      end
    end
  end

  def run : Void
    @workers.size.times { @start_channel.send(nil) }
    @workers.size.times { @done_channel.receive }
  end

  def node_by_id(node_id : UInt32) : N
    worker = worker_for_node(node_id)
    local_idx = worker_local_node_idx(node_id)
    worker.nodes[local_idx]
  end

  private def build_nodes
    @layer_sizes.each_with_index(0_u32) do |size, layer_idx|
      size.times do |node_idx|
        node_id = node_id(layer_idx, node_idx)
        worker_for_node(node_id).add_node(node_id)
      end
    end
  end

  private def build_routes : Void
    return if @layer_sizes.size < 2

    (@layer_sizes.size - 1).times do |layer_idx|
      next_layer_idx = layer_idx.to_u32 + 1_u32
      next_layer_size = @layer_sizes[next_layer_idx]

      next_routes = Array(Route).new(next_layer_size.to_i)
      next_layer_size.times do |target_node_idx|
        target_id = node_id(next_layer_idx, target_node_idx)
        next_routes << Route.new(
          worker_id_for_node(target_id),
          worker_local_node_idx(target_id)
        )
      end

      current_layer_size = @layer_sizes[layer_idx]
      current_layer_size.times do |source_node_idx|
        src_id = node_id(layer_idx.to_u32, source_node_idx)
        src_node = node_by_id(src_id)
        next_routes.each do |route|
          src_node.add_route(route)
        end
      end
    end
  end

  private def build_workers
    @worker_count.times do |idx|
      @workers << Worker(N, P, R).new(idx, self, @layer_sizes.size.to_u32)
    end
  end

  private def build_worker_layer_starts
    next_index = StaticArray(UInt32, 8).new(0u32)
    @layer_sizes.each_with_index do |layer_size, layer_idx|
      base = layer_size >> WORKERS_SHIFT
      remainder = layer_size & WORKERS_MASK
      MAX_WORKERS.times do |worker|
        @worker_layer_starts[worker * @layer_count + layer_idx] = next_index[worker]
        owned = base
        owned += 1u32 if worker < remainder
        next_index[worker] += owned
      end
    end
  end

  def worker_layer_start(worker_id : UInt32, layer_idx : UInt32) : UInt32
    @worker_layer_starts[worker_id.to_i * @layer_count + layer_idx.to_i]
  end

  def reset(start_time : UInt64, end_time : UInt64) : Void
    @start_time = start_time
    last_process_time = end_time + ((@layer_sizes.size - 1) * @layer_latency)
    @workers.each(&.reset(start_time, last_process_time))
    @sync_mgr.reset(start_time, last_process_time)
  end

  def input(node_id : UInt32, process_at : UInt64, raw_payload) : Void
    payload = uninitialized P
    {% if P == Tuple(UInt8, Float64) %}
      # If raw_payload is a tuple like {label, value}, extract and cast them
      tuple_payload = raw_payload.as(Tuple(UInt8, Float64))
      payload = {tuple_payload[0].to_u8, tuple_payload[1].to_f64}
    {% elsif P == UInt64 %}
      # If the network expects a UInt64, convert the raw input
      payload = 1_u64
    {% else %}
      # Fallback cast
      payload = raw_payload.as(P)
    {% end %}
    target_worker_id = worker_id_for_node(node_id)
    target_local_idx = worker_local_node_idx(node_id)
    @workers[target_worker_id].schedule(target_local_idx, process_at, payload)
  end

  def propagate(from_node : N, from_time : UInt64, process_result : R) : Nil
    {% if R == Tuple(UInt8, Bool) %}
      return unless process_result[1]
    {% end %}

    # apply_vdsp(layer_idx, post_neuron, time) if @training
    # layer.voltages[post_neuron] = V_RESET
    # layer.consider_lateral_inhibition(post_neuron)


    target_time = from_time + @layer_latency
    from_node.routes.each do |route|
      payload = uninitialized P
      {% if R == Tuple(UInt8, Bool) %}
        payload = {process_result[0], route.weight}
      {% else %}
        payload = process_result
      {% end %}
      @workers[route.target_worker_id].schedule(route.target_local_node_idx, target_time, payload)
    end
  end

  def horizon_next_tick(worker_id : UInt32) : UInt64
    @sync_mgr.horizon_next_tick(worker_id)
  end

  def record_progress(worker_id : UInt32, worker_next_tick : UInt64) : Void
    @sync_mgr.record_progress(worker_id, worker_next_tick)
  end

  def layer_idx(node_id : UInt32)
    node_id >> NODES_PER_LAYER_SHIFT
  end

  def worker_local_node_idx(node_id : UInt32) : UInt32
    layer_idx = layer_idx(node_id)
    node_idx_within_layer = node_idx_within_layer(node_id)
    worker_id = worker_id_for_node(node_id)
    worker_layer_start(worker_id, layer_idx) + (node_idx_within_layer >> WORKERS_SHIFT)
  end

  def node_idx_within_layer(node_id : UInt32)
    node_id & NODES_PER_LAYER_MASK
  end

  def worker_id_for_node(node_id : UInt32)
    node_id & WORKERS_MASK
  end

  def node_id(layer_idx : UInt32, node_idx_in_layer : UInt32)
    (layer_idx << NODES_PER_LAYER_SHIFT) | node_idx_in_layer
  end

  def worker_for_node(node_id : UInt32) : Worker
    @workers[worker_id_for_node(node_id)]
  end

end
