require "./wheel"
require "./cross_worker_comm"

struct LayerBounds
  getter start_id : UInt32
  getter end_id : UInt32

  def initialize(@start_id : UInt32, @end_id : UInt32)
  end
end

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

  # Called by another worker (source_id) to send a message to this worker.
  def enqueue_from(source_id : Int32, target_node : UInt32, delay : UInt64, payload : Float64) : Void
    @incoming_queues[source_id].push(target_node, delay, payload)
  end

  # Drain all incoming queues into this worker's wheel
  def drain_all_incoming : Void
    @incoming_queues.each(&.drain_into(@wheel))
  end
end
