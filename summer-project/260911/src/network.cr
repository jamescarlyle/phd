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

  def initialize(layer_sizes : Array(Int32), worker_count : Int32, @training = false)
    @sync_mgr = SyncManager.new(worker_count)
    @layer_bounds = Array(LayerBounds).new
    total_nodes_count = 0_u32
    layer_sizes.each do |size|
      start_id = total_nodes_count
      end_id = total_nodes_count + size.to_u32 - 1_u32
      @layer_bounds << LayerBounds.new(start_id, end_id)
      total_nodes_count += size.to_u32
    end

    @all_nodes = Array(Node).new
    node_id = 0_u32
    layer_sizes.each_with_index do |size, layer_idx|
      size.times do
        @all_nodes << Node.new(node_id, layer_idx)
        node_id += 1_u32
      end
    end

    @workers = Array(Worker).new(worker_count) do |i|
      Worker.new(i, current_time: 0, worker_count: worker_count)
    end
    @router = Router.new(@workers, @layer_bounds, worker_count)
  end

  def run() : Void
    @workers.each do |worker|
      spawn do
        worker_id = worker.id
        loop do
          local_time = worker.wheel.current_time

          unless @sync_mgr.update_and_sync(worker_id, local_time)
            Fiber.yield
            next
          end

          worker.drain_all_incoming

          worker.wheel.tick do |event|
            node = @all_nodes[event.target_node]
            new_state = node.process(event.payload)
            @router.dispatch(node, new_state, worker_id)
          end
        end
      end
    end
  end

  def input(node_id : UInt32, process_at : UInt64) : Void
    worker_id = (node_id % WORKER_COUNT).to_i
    @workers[worker_id].enqueue(worker_id, node_id, process_at, 1.0)
  end

  def reset_network(first_event_time : UInt64)
  end


end
