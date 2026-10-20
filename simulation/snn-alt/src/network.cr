require "./constant"
require "./node/*"
require "./sync_manager.cr"
require "./worker"

# Sample allocation of 8 nodes across 3 layers to 4 workers:
# | Global node | Layer | Worker | Worker-local node index |
# | ----------- | ----- | ------ | ----------------------- |
# | 0           | 0     | 0      | 0                       |
# | 1           | 0     | 1      | 0                       |
# | 2           | 0     | 2      | 0                       |
# | 3           | 0     | 3      | 0                       |
# | 4           | 1     | 0      | 1                       |
# | 5           | 1     | 1      | 1                       |
# | 6           | 1     | 2      | 1                       |
# | 7           | 2     | 0      | 2                       |
# | 8           | 2     | 1      | 2                       |

class Network(N, P, R)
  getter layer_sizes : Slice(UInt16)
  getter layer_offsets : Slice(UInt32)
  getter worker_count : UInt8
  getter total_node_count : UInt32

  getter node_allocations : Slice(NodeAllocation)

  getter forward_route_offsets : Slice(UInt32)
  getter forward_routes : Slice(ForwardRoute)

  getter backward_route_offsets : Slice(UInt32)
  getter backward_routes : Slice(BackwardRoute)

  getter worker_weight_offsets : Slice(UInt32)
  getter workers : Slice(Worker(N, P, R))

  getter sync_mgr
  getter layer_latency
  @start_channel : Channel(Nil) = Channel(Nil).new
  @done_channel : Channel(Nil) = Channel(Nil).new


  def initialize(
    layer_sizes : Array(UInt16),
    worker_count : UInt8,
    initial_weight_value : Float64 = 0.0,
    @layer_latency : UInt64 = LAYER_LATENCY,
    @max_drift : UInt64 = MAX_DRIFT,
    @training = false
  )
    raise ArgumentError.new("At least two layers are required") if layer_sizes.size < 2
    raise ArgumentError.new("At least one worker is required") if worker_count.zero?
    raise ArgumentError.new("At most #{MAX_WORKERS} workers are supported") if worker_count > MAX_WORKERS

    layer_sizes.each do |layer_size|
      if layer_size > MAX_NODES_PER_LAYER
        raise ArgumentError.new(
          "Layer size #{layer_size} exceeds #{MAX_NODES_PER_LAYER}"
        )
      end
    end

    @worker_count = worker_count
    @workers = Slice(Worker(N, P, R)).empty
    @sync_mgr = SyncManager.new(@worker_count, @layer_latency, @max_drift)
    @layer_sizes = copy_layer_sizes(layer_sizes)
    @layer_offsets = build_layer_offsets
    @total_node_count = layer_offsets[layer_offsets.size - 1]

    @node_allocations = build_node_allocations

    @forward_route_offsets = Slice(UInt32).new(
      total_node_count.to_i32! + 1,
      0_u32
    )
    @forward_routes = Slice(ForwardRoute).new(
      total_forward_route_count.to_i32!
    ) do
      ForwardRoute.new(0_u8, 0_u16)
    end

    build_forward_routes

    @backward_route_offsets = Slice(UInt32).new(
      total_node_count.to_i32! + 1,
      0_u32
    )
    @backward_routes = Slice(BackwardRoute).new(
      total_backward_route_count.to_i32!
    ) do
      BackwardRoute.new(0_u8, 0_u16, 0_u32)
    end

    build_backward_route_offsets
    @worker_weight_offsets = build_worker_weight_offsets
    build_backward_routes

    @workers = build_workers(initial_weight_value)
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

  def layer_count : UInt32
    layer_sizes.size.to_u32
  end

  def global_node_index(layer_index : UInt32, layer_local_node_index : UInt16) : UInt32
    layer_offsets[layer_index] + layer_local_node_index
  end

  def node_allocation(global_node_index : UInt32) : NodeAllocation
    node_allocations[global_node_index]
  end

  def worker_for_global_node_index(global_node_index : UInt32) : Worker(N, P, R)
    allocation = node_allocations[global_node_index]

    workers[allocation.worker_id]
  end

  def forward_route_range(global_node_index : UInt32) : Range(UInt32, UInt32)
    forward_route_offsets[global_node_index]...forward_route_offsets[global_node_index + 1]
  end

  def backward_route_range(global_node_index : UInt32) : Range(UInt32, UInt32)
    backward_route_offsets[global_node_index]...backward_route_offsets[global_node_index + 1]
  end

  private def copy_layer_sizes(
    layer_sizes : Array(UInt16)
  ) : Slice(UInt16)
    copied_sizes = Slice(UInt16).new(layer_sizes.size)

    layer_sizes.each_with_index do |layer_size, layer_index|
      copied_sizes[layer_index] = layer_size
    end

    copied_sizes
  end

  private def build_layer_offsets : Slice(UInt32)
    offsets = Slice(UInt32).new(layer_sizes.size + 1, 0_u32)

    running_node_count = 0_u32

    layer_sizes.each_with_index do |layer_size, layer_index|
      offsets[layer_index] = running_node_count
      running_node_count += layer_size.to_u32
    end

    offsets[layer_sizes.size] = running_node_count
    offsets
  end

  private def build_node_allocations : Slice(NodeAllocation)
    allocations =
      Slice(NodeAllocation).new(total_node_count.to_i32!) do |global_node_index|
        NodeAllocation.new(
          0_u8,
          0_u16,
          global_node_index.to_u32!
        )
      end

    worker_node_counts = Slice(UInt16).new(worker_count, 0_u16)
    global_node_index = 0_u32

    layer_sizes.each do |layer_size|
      worker_index = 0_u32

      layer_size.times do
        worker_id = worker_index.to_u8!
        worker_local_node_index = worker_node_counts[worker_id]

        allocations[global_node_index] = NodeAllocation.new(
          worker_id,
          worker_local_node_index,
          global_node_index
        )

        worker_node_counts[worker_id] += 1_u16

        worker_index += 1_u32
        worker_index &= MAX_WORKERS_MASK

        global_node_index += 1_u32
      end
    end

    allocations
  end

  private def total_forward_route_count : UInt32
    total_route_count = 0_u32

    (layer_count - 1).times do |layer_index|
      source_layer_size = layer_sizes[layer_index].to_u32
      target_layer_size = layer_sizes[layer_index + 1].to_u32

      total_route_count += source_layer_size * target_layer_size
    end

    total_route_count
  end

  private def total_backward_route_count : UInt32
    total_forward_route_count
  end

  private def build_forward_routes : Nil
    route_index = 0_u32

    (layer_count - 1).times do |source_layer_index|
      source_layer_size = layer_sizes[source_layer_index].to_u32
      target_layer_index = source_layer_index + 1_u32
      target_layer_size = layer_sizes[target_layer_index].to_u32

      source_layer_first_global_index = layer_offsets[source_layer_index]
      target_layer_first_global_index = layer_offsets[target_layer_index]

      source_layer_size.times do |source_layer_local_node_index|
        source_global_node_index =
          source_layer_first_global_index + source_layer_local_node_index

        forward_route_offsets[source_global_node_index] = route_index

        target_layer_size.times do |target_layer_local_node_index|
          target_global_node_index =
            target_layer_first_global_index + target_layer_local_node_index

          target_allocation = node_allocations[target_global_node_index]

          forward_routes[route_index] = ForwardRoute.new(
            target_allocation.worker_id,
            target_allocation.worker_local_node_index
          )

          route_index += 1_u32
        end
      end
    end

    output_layer_start = layer_offsets[layer_count - 1]

    (output_layer_start..total_node_count).each do |global_node_index|
      forward_route_offsets[global_node_index] = route_index
    end
    # forward_route_offsets[total_node_count] = route_index
  end

  private def build_backward_route_offsets : Nil
    route_index = 0_u32

    (layer_count - 1).times do |source_layer_index|
      source_layer_size = layer_sizes[source_layer_index].to_u32
      target_layer_index = source_layer_index + 1_u32
      target_layer_size = layer_sizes[target_layer_index].to_u32

      target_layer_first_global_index = layer_offsets[target_layer_index]

      target_layer_size.times do |target_layer_local_node_index|
        target_global_node_index =
          target_layer_first_global_index + target_layer_local_node_index

        backward_route_offsets[target_global_node_index] = route_index

        route_index += source_layer_size
      end
    end

    backward_route_offsets[total_node_count] = route_index
  end

  private def build_worker_weight_offsets : Slice(UInt32)
    worker_weight_counts = Slice(UInt32).new(worker_count, 0_u32)

    total_node_count.times do |global_node_index|
      target_allocation = node_allocations[global_node_index]
      target_worker_id = target_allocation.worker_id

      backward_start = backward_route_offsets[global_node_index]
      backward_end = backward_route_offsets[global_node_index + 1]

      incoming_edge_count = backward_end - backward_start

      worker_weight_counts[target_worker_id] += incoming_edge_count
    end

    worker_weight_offsets =
      Slice(UInt32).new(worker_count.to_i32! + 1, 0_u32)

    worker_count.times do |worker_index|
      worker_weight_offsets[worker_index + 1] =
        worker_weight_offsets[worker_index] +
        worker_weight_counts[worker_index]
    end

    worker_weight_offsets
  end

  private def build_backward_routes : Nil
    route_index = 0_u32
    worker_next_weight_index = Slice(UInt32).new(worker_count, 0_u32)

    (layer_count - 1).times do |source_layer_index|
      source_layer_size = layer_sizes[source_layer_index].to_u32
      target_layer_index = source_layer_index + 1_u32
      target_layer_size = layer_sizes[target_layer_index].to_u32

      source_layer_first_global_index = layer_offsets[source_layer_index]
      target_layer_first_global_index = layer_offsets[target_layer_index]

      target_layer_size.times do |target_layer_local_node_index|
        target_global_node_index =
          target_layer_first_global_index + target_layer_local_node_index

        target_allocation = node_allocations[target_global_node_index]
        target_worker_id = target_allocation.worker_id

        backward_route_offsets[target_global_node_index] = route_index

        source_layer_size.times do |source_layer_local_node_index|
          source_global_node_index =
            source_layer_first_global_index + source_layer_local_node_index

          source_allocation = node_allocations[source_global_node_index]

          worker_local_weight_index =
            worker_weight_offsets[target_worker_id] +
            worker_next_weight_index[target_worker_id]

          backward_routes[route_index] = BackwardRoute.new(
            source_allocation.worker_id,
            source_allocation.worker_local_node_index,
            worker_local_weight_index
          )

          worker_next_weight_index[target_worker_id] += 1_u32
          route_index += 1_u32
        end
      end
    end

    backward_route_offsets[total_node_count] = route_index
  end

  private def build_workers(
    initial_weight_value : Float64
  ) : Slice(Worker(N, P, R))
    worker_node_counts = compute_worker_node_counts

    Slice(Worker(N, P, R)).new(worker_count.to_i32!) do |worker_index|
      build_worker(
        worker_index.to_u8!,
        worker_node_counts[worker_index],
        initial_weight_value
      )
    end
  end

  private def build_worker(
    worker_id : UInt8,
    node_count : UInt32,
    initial_weight_value : Float64
  ) : Worker(N, P, R)
    weight_start = worker_weight_offsets[worker_id]
    weight_end = worker_weight_offsets[worker_id + 1]
    weight_count = weight_end - weight_start

    nodes = Slice(N).new(node_count.to_i32!) do
      N.new
    end

    weight_values =
      Slice(Float64).new(weight_count.to_i32!, initial_weight_value)

    Worker(N, P, R).new(
      network: self,
      worker_id: worker_id,
      node_count: node_count,
      nodes: nodes,
      weight_values: weight_values,
      forward_route_offsets: forward_route_offsets,
      forward_routes: forward_routes,
      backward_route_offsets: backward_route_offsets,
      backward_routes: backward_routes
    )
  end

  private def compute_worker_node_counts : Slice(UInt32)
    worker_node_counts = Slice(UInt32).new(worker_count, 0_u32)

    node_allocations.each do |allocation|
      worker_node_counts[allocation.worker_id] += 1_u32
    end

    worker_node_counts
  end

  def reset(start_time : UInt64, end_time : UInt64) : Void
    @start_time = start_time
    last_process_time = end_time + ((@layer_sizes.size - 1) * @layer_latency)
    @workers.each(&.reset(start_time, last_process_time))
    @sync_mgr.reset(start_time, last_process_time)
  end

  def horizon_next_tick(worker_id : UInt32) : UInt64
    @sync_mgr.horizon_next_tick(worker_id)
  end

  def record_progress(worker_id : UInt32, worker_next_tick : UInt64) : Void
    @sync_mgr.record_progress(worker_id, worker_next_tick)
  end

  def input(layer_0_node_index : UInt16, process_at : UInt64, raw_payload) : Void
    allocation = node_allocations[layer_0_node_index]
    payload = uninitialized P
    {% if P == Float64 %}
      payload = raw_payload
    {% elsif P == UInt64 %}
      payload = 1_u64
    {% else %}
      payload = raw_payload.as(P)
    {% end %}
    @workers[allocation.worker_id].schedule(layer_0_node_index.to_u32!, allocation.worker_local_node_index, process_at, payload)
  end


  def propagate(from_global_node_index : UInt32, from_time : UInt64, process_result : R) : Nil
    {% if R == Bool %}
      return unless process_result
    {% end %}

    target_time = from_time + @layer_latency

    payload = uninitialized P
    forward_route_range(from_global_node_index).each do |route_index|
      route = forward_routes[route_index]

      {% if R == Bool %}
        payload = 1
      {% else %}
        payload = 1
      {% end %}

      workers[route.target_worker_id].schedule(
        from_global_node_index,
        route.target_worker_local_node_index,
        target_time,
        payload
      )
    end
  end
end
