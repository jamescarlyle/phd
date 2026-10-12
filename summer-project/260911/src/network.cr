require "./constants"
require "./sync_manager"
require "./worker"
require "./router"

struct LayerBounds
  getter start_id : UInt32
  getter end_id : UInt32

  def initialize(@start_id : UInt32, @end_id : UInt32)
  end
end

class Network
  property? training : Bool
  getter all_nodes : Array(Node)
  getter layer_bounds : Array(LayerBounds)
  getter workers : Array(Worker)
  getter router : Router
  getter sync_mgr : SyncManager

  def initialize(layer_sizes : Array(Int32), @worker_count : Int32, @training = false)
    @sync_mgr = SyncManager.new(@worker_count)
    @layer_bounds = build_layer_bounds(layer_sizes)
    @all_nodes = build_nodes(layer_sizes)
    @workers = build_workers(@worker_count)
    @router = Router.new(@workers, @layer_bounds, worker_count)
  end

  # Build layer bounds from layer sizes.
  def build_layer_bounds(layer_sizes : Array(Int32)) : Array(LayerBounds)
    bounds = Array(LayerBounds).new
    total_nodes_count = 0_u32

    layer_sizes.each do |size|
      start_id = total_nodes_count
      end_id = total_nodes_count + size.to_u32 - 1_u32
      bounds << LayerBounds.new(start_id, end_id)
      total_nodes_count += size.to_u32
    end

    bounds
  end

  # Build all nodes with correct IDs and layer indices.
  def build_nodes(layer_sizes : Array(Int32)) : Array(Node)
    nodes = Array(Node).new
    node_id = 0_u32

    layer_sizes.each_with_index do |size, layer_idx|
      size.times do
        nodes << Node.new(node_id, layer_idx)
        node_id += 1_u32
      end
    end

    nodes
  end

  # Build worker instances.
  def build_workers(worker_count : Int32) : Array(Worker)
    Array(Worker).new(worker_count) do |i|
      Worker.new(i, initial_time: 0, worker_count: worker_count)
    end
  end

  # Run the network with one fiber per worker.
  def run : Void
    @workers.each do |worker|
      spawn(name: "worker #{worker.id}") do
        run_worker_loop(worker)
      end
    end
  end

  # Top-level fiber driver.
  def run_worker_loop(worker : Worker) : Void
    loop do
      allowed = run_worker_loop_iteration(worker)
      Fiber.yield unless allowed
    end
  end

  # Single discrete step: fully testable in a single thread with no mocks
  def run_worker_loop_iteration(worker : Worker) : Bool
    return false unless @sync_mgr.active?
    worker_id = worker.id
    # Drain incoming cross-thread / loader events into local wheel.
    worker.drain_all_incoming
    # Determine safe horizon (respecting peer lookahead and loader ceiling)
    horizon = @sync_mgr.safe_time(worker_id)
    # If we have reached or exceeded what is safe, we cannot advance yet.
    return false unless horizon > worker.clock.current_time


    while worker.clock.current_time < horizon
      # Drain cross-worker queue BEFORE advancing each tick
      worker.drain_all_incoming

      worker.clock.tick do |event|
        node = @all_nodes[event.target_node]
        new_state = node.process(event.payload)
        @router.dispatch(node, new_state, worker_id)
      end

      @sync_mgr.record_progress(worker_id, worker.clock.current_time)
    end



    # # Burst process local wheel up to the safe horizon.
    # worker.clock.advance_to(horizon) do |event|
    #   node = @all_nodes[event.target_node]
    #   new_state = node.process(event.payload)
    #   @router.dispatch(node, new_state, worker_id)
    # end
    # Worker is now exactly at `horizon`. Report to sync manager.
    @sync_mgr.record_progress(worker_id, worker.clock.current_time)
    # Successfully made progress.
    true
  end

  # Enqueue an input event to a specific node.
  def input(node_id : UInt32, process_at : UInt64) : Void
    worker_id = worker_id_for_node(node_id)
    @workers[worker_id].enqueue_at(worker_id, node_id, process_at, 1.0)
    # @sync_mgr.update_loader_time(process_at)
  end

  # Determine which worker should handle a given node.
  def worker_id_for_node(node_id : UInt32) : Int32
    (node_id % @worker_count).to_i
  end

  # Reset network state for a new simulation run.
  def reset(end_time : UInt64) : Void
    # Reset each worker's clock time.
    @workers.each(&.reset)
    # Reset SyncManager global minimum and all worker clocks.
    @sync_mgr.reset(end_time)
    # Optionally clear node states, queues, etc., depending on design.
  end
end
