require "./constant"
require "./node_key"
require "./route"
require "./node/*"
require "./sync_manager"
require "./worker"

class Network(N, P, R)
  getter layer_sizes : Slice(UInt16)
  getter layer_nodes : Array(Slice(NodeKey))
  getter worker_count : UInt8
  getter total_node_count : UInt32
  getter workers : Slice(Worker(N, P, R))
  getter sync_mgr : SyncManager
  getter layer_latency : UInt64
  getter max_drift : UInt64
  getter slot_capacity : UInt32
  getter? training : Bool
  getter start_time : UInt64 = 0_u64
  getter end_time : UInt64 = 0_u64

  @end_time_exclusive : UInt64 = 0_u64
  @configured : Bool = false
  @workers_started : Bool = false
  @running = Atomic(Bool).new(false)
  @cancelled = Atomic(Bool).new(false)
  @failed = Atomic(Bool).new(false)
  @lifecycle_lock = Mutex.new
  @start_channels : Array(Channel(Nil))
  @done_channel : Channel(Exception?)

  def initialize(
    layer_sizes : Array(UInt16),
    @worker_count : UInt8 = MAX_WORKERS,
    initial_weight_value : Float64 = 0.0,
    @layer_latency : UInt64 = LAYER_LATENCY,
    @max_drift : UInt64 = MAX_DRIFT,
    @training : Bool = false,
    @slot_capacity : UInt32 = BUFFER_CAPACITY,
    autostart : Bool = true
  )
    raise ArgumentError.new("At least two layers are required.") if layer_sizes.size < 2
    unless 1 <= @worker_count && @worker_count <= MAX_WORKERS
      raise ArgumentError.new("Worker count must be between 1 and #{MAX_WORKERS}")
    end
    raise ArgumentError.new("Layer latency must be positive.") if @layer_latency.zero?
    raise ArgumentError.new("Maximum drift must be positive.") if @max_drift.zero?
    if @max_drift > @layer_latency
      raise ArgumentError.new("Maximum drift must not exceed layer latency.")
    end
    unless @slot_capacity > 0 && (@slot_capacity & (@slot_capacity - 1)) == 0
      raise ArgumentError.new("Slot capacity must be a positive power of two.")
    end
    layer_sizes.each do |size|
      if size.to_u32 > MAX_NODES_PER_LAYER
        raise ArgumentError.new("Layer size #{size} exceeds #{MAX_NODES_PER_LAYER}")
      end
    end
    @layer_sizes = Slice(UInt16).new(layer_sizes.size) do |index|
      layer_sizes[index]
    end
    @layer_nodes = [] of Slice(NodeKey)
    @total_node_count = 0_u32
    @workers = Slice(Worker(N, P, R)).empty
    @sync_mgr = SyncManager.new(@worker_count.to_u32, @layer_latency, @max_drift)
    @start_channels = Array(Channel(Nil)).new(@worker_count.to_i32) do
      Channel(Nil).new
    end
    @done_channel = Channel(Exception?).new(@worker_count.to_i32)
    worker_node_counts = build_layer_nodes
    total = worker_node_counts.reduce(0_u64) do |sum, count|
      sum + count.to_u64
    end
    if total > UInt32::MAX.to_u64
      raise ArgumentError.new("Total node count exceeds UInt32 capacity.")
    end
    @total_node_count = total.to_u32
    build_workers(worker_node_counts, initial_weight_value)
    start_workers if autostart
  end

  def layer_count : UInt32
    @layer_sizes.size.to_u32
  end

  def running? : Bool
    @running.get
  end

  def failed? : Bool
    @failed.get
  end

  def reset(first_event_time : UInt64, last_event_time : UInt64) : Nil
    @lifecycle_lock.synchronize do
      raise RuntimeError.new("Cannot reset a running network.") if @running.get
      if last_event_time < first_event_time
        raise ArgumentError.new("End time must not precede start time.")
      end
      last_event_plus_latency = last_event_time.to_u128 + (@layer_sizes.size - 1).to_u128 * @layer_latency.to_u128
      if last_event_plus_latency > UInt64::MAX.to_u128
        raise ArgumentError.new("Pipeline finish time exceeds UInt64 capacity.")
      end
      end_time_exclusive = last_event_plus_latency.to_u64 + 1
      clear_buffers = @failed.get || @cancelled.get
      @start_time = first_event_time
      @end_time = last_event_time
      @workers.each do |worker|
        worker.reset(first_event_time, end_time_exclusive, clear_buffers)
      end
      @sync_mgr.reset(first_event_time, end_time_exclusive)
      @end_time_exclusive = end_time_exclusive
      @cancelled.set(false)
      @failed.set(false)
      @configured = true
    end
    nil
  end

  def input(layer_0_node_index : UInt16, process_at : UInt64, raw_payload) : Bool
    {% if flag?(:verify_parameters) %}
      unless @configured
        raise RuntimeError.new("Network must be reset before receiving input.")
      end
      if @failed.get
        raise RuntimeError.new("Network failed; a quiescent reset is required before reuse.")
      end
      if layer_0_node_index >= @layer_nodes[0].size.to_u16
        raise IndexError.new("Invalid layer-0 node index: #{layer_0_node_index}")
      end
      if  process_at < @start_time || process_at > @end_time
        raise ArgumentError.new("Input time #{process_at} is before #{@start_time} or equal or more than #{@end_time_exclusive})")
      end
    {% end %}
    key = @layer_nodes[0][layer_0_node_index]
    payload = uninitialized P
    {% if P == UInt64 %}
      payload = 1_u64
    {% elsif P == Float64 %}
      payload = raw_payload.to_f64
    {% else %}
      payload = raw_payload.as(P)
    {% end %}

    @workers[key.worker_id].schedule(key.worker_local_node_index, nil, process_at, payload)
  end

  def horizon_next_tick(worker_id : UInt32) : UInt64
    @sync_mgr.horizon_next_tick(worker_id)
  end

  def record_progress(worker_id : UInt32, worker_next_tick : UInt64) : Nil
    @sync_mgr.record_progress(worker_id, worker_next_tick)
    nil
  end

  def run : Nil
    @lifecycle_lock.synchronize do
      raise RuntimeError.new("Network is already running.") if @running.get
      raise RuntimeError.new("Network must be reset before running.") unless @configured
      raise RuntimeError.new("Network failed; a quiescent reset is required before reuse.") if @failed.get

      start_workers unless @workers_started
      @cancelled.set(false)
      @running.set(true)
    end

    begin
      @start_channels.each do |channel|
        channel.send(nil)
      end
      first_error : Exception? = nil
      @worker_count.to_i32.times do
        if error = @done_channel.receive
          puts "Worker exception: #{error.message}"
          first_error ||= error
        end
      end
      if error = first_error
        @workers.each(&.debug_pending)
        @failed.set(true)
        raise error
      end
    ensure
      @running.set(false)
    end
    nil
  end

  private def build_layer_nodes : Slice(UInt32)
    worker_node_counts = Slice(UInt32).new(@worker_count.to_i32, 0_u32)
    local_index_capacity = UInt16::MAX.to_u32 + 1_u32
    @layer_sizes.each do |layer_size|
      nodes = Slice(NodeKey).new(layer_size.to_i32) do |layer_local_index|
        worker_index = layer_local_index % @worker_count.to_i32
        local_index = worker_node_counts[worker_index]
        raise ArgumentError.new("Worker #{worker_index} exceeds UInt16 node-address capacity.") if local_index >= local_index_capacity
        key = NodeKey.new(worker_index.to_u8, local_index.to_u16)
        worker_node_counts[worker_index] = local_index + 1_u32
        key
      end
      @layer_nodes << nodes
    end
    worker_node_counts
  end

  private def build_route_offsets(counts : Slice(UInt32)) : Slice(UInt32)
    offsets = Slice(UInt32).new(counts.size + 1, 0_u32)
    running_count = 0_u64
    counts.each_with_index do |count, index|
      running_count += count.to_u64
      raise ArgumentError.new("Worker route count exceeds supported slice capacity.") if running_count > Int32::MAX.to_u64
      offsets[index + 1] = running_count.to_u32
    end
    offsets
  end

  private def build_workers(worker_node_counts : Slice(UInt32), initial_weight_value : Float64) : Nil
    worker_count = @worker_count.to_i32
    outgoing_counts = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      Slice(UInt32).new(worker_node_counts[worker_index].to_i32, 0_u32)
    end

    incoming_counts = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      Slice(UInt32).new(worker_node_counts[worker_index].to_i32, 0_u32)
    end

    @layer_nodes.each_with_index do |layer, layer_index|
      incoming_degree = layer_index.zero? ? 0_u32 : @layer_sizes[layer_index - 1].to_u32
      outgoing_degree = layer_index + 1 < @layer_sizes.size ? @layer_sizes[layer_index + 1].to_u32 : 0_u32

      layer.each do |key|
        outgoing_counts[key.worker_id][key.worker_local_node_index] = outgoing_degree
        incoming_counts[key.worker_id][key.worker_local_node_index] = incoming_degree
      end
    end

    forward_offsets = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      build_route_offsets(outgoing_counts[worker_index])
    end
    backward_offsets = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      build_route_offsets(incoming_counts[worker_index])
    end
    forward_routes = Array(Slice(ForwardRoute)).new(worker_count) do |worker_index|
      Slice(ForwardRoute).new(forward_offsets[worker_index].last.to_i32) do
        ForwardRoute.new(0_u8, 0_u16, 0_u32)
      end
    end
    backward_routes = Array(Slice(BackwardRoute)).new(worker_count) do |worker_index|
      Slice(BackwardRoute).new(backward_offsets[worker_index].last.to_i32) do
        BackwardRoute.new(0_u8, 0_u16, 0_u32, 0_u32)
      end
    end
    forward_cursors = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      forward_offsets[worker_index][0, worker_node_counts[worker_index].to_i32].dup
    end
    backward_cursors = Array(Slice(UInt32)).new(worker_count) do |worker_index|
      backward_offsets[worker_index][0, worker_node_counts[worker_index].to_i32].dup
    end

    (@layer_nodes.size - 1).times do |layer_index|
      source_layer = @layer_nodes[layer_index]
      target_layer = @layer_nodes[layer_index + 1]
      source_layer.each do |source|
        source_worker = source.worker_id
        source_local = source.worker_local_node_index
        target_layer.each do |target|
          target_worker = target.worker_id
          target_local = target.worker_local_node_index
          forward_index = forward_cursors[source_worker][source_local]
          backward_index = backward_cursors[target_worker][target_local]
          forward_routes[source_worker][forward_index] = ForwardRoute.new(
            target_worker,
            target_local,
            backward_index
          )
          backward_routes[target_worker][backward_index] = BackwardRoute.new(
            source_worker,
            source_local,
            forward_index,
            backward_index
          )
          forward_cursors[source_worker][source_local] =
            forward_index + 1_u32
          backward_cursors[target_worker][target_local] =
            backward_index + 1_u32
        end
      end
    end

    worker_count.times do |worker_index|
      worker_node_counts[worker_index].to_i32.times do |local_index|
        unless forward_cursors[worker_index][local_index] == forward_offsets[worker_index][local_index + 1]
          raise RuntimeError.new("Incomplete forward-route construction.")
        end
        unless backward_cursors[worker_index][local_index] == backward_offsets[worker_index][local_index + 1]
          raise RuntimeError.new("Incomplete backward-route construction.")
        end
      end
    end

    @workers = Slice(Worker(N, P, R)).new(worker_count) do |worker_index|
      node_count = worker_node_counts[worker_index]
      weight_count = backward_routes[worker_index].size

      nodes = Slice(N).new(node_count.to_i32) do
        N.new
      end
      weights = Slice(Float64).new(weight_count, initial_weight_value)

      Worker(N, P, R).new(
        network: self,
        worker_id: worker_index.to_u8,
        node_count: node_count,
        nodes: nodes,
        weight_values: weights,
        forward_route_offsets: forward_offsets[worker_index],
        forward_routes: forward_routes[worker_index],
        backward_route_offsets: backward_offsets[worker_index],
        backward_routes: backward_routes[worker_index],
        slot_capacity: @slot_capacity
      )
    end
    nil
  end

  private def start_workers : Nil
    return if @workers_started
    @workers.each do |worker|
      start_channel = @start_channels[worker.worker_id]
      spawn(name: "worker #{worker.worker_id}") do
        loop do
          start_channel.receive
          error : Exception? = nil
          begin
            until @cancelled.get
              case worker.iterate
              when :break
                unless worker.drained?
                  raise RuntimeError.new("Worker #{worker.worker_id} completed with undrained clock.")
                end
                break
              when :yield
                Fiber.yield
              end
            end
          rescue ex : Exception
            error = ex
            @failed.set(true)
            @cancelled.set(true)
          ensure
            @done_channel.send(error)
          end
        end
      end
    end
    @workers_started = true
    nil
  end
end
