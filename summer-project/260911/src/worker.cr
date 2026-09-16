require "./wheel"
require "./cross_worker_comm"

class Worker
  getter id : Int32
  getter wheel : HierarchicalWheel
  getter incoming_queues : Array(CrossWorkerQueue)

  def initialize(@id : Int32, current_time : UInt64, worker_count : Int32)
    @wheel = HierarchicalWheel.new(current_time)
    @incoming_queues = Array(CrossWorkerQueue).new(worker_count) do
      CrossWorkerQueue.new
    end
  end

  # Called by externally (from_worker_id) to send a message to this worker.
  def enqueue(from_worker_id : Int32, target_node_id : UInt32, delay : UInt64, payload : Float64) : Void
    process_at = @wheel.current_time + delay
    enqueue_at(from_worker_id, target_node_id, process_at, payload)
  end

  def enqueue_at(from_worker_id : Int32, target_node_id : UInt32, process_at : UInt64, payload : Float64) : Void
    @incoming_queues[from_worker_id].push(Event.new(target_node_id, process_at, payload))
  end

  # Drain all incoming queues into this worker's wheel
  def drain_all_incoming : Void
    @incoming_queues.each(&.drain_into(@wheel))
  end
end
