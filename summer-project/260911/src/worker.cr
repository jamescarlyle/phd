require "./hierarchical_clock"
require "./cross_worker_comm"

class Worker
  getter id : Int32
  getter clock : HierarchicalClock

  def initialize(@id : Int32, initial_time : UInt64, worker_count : Int32)
    @clock = HierarchicalClock.new(initial_time)
    @incoming_queues = Array(CrossWorkerQueue).new(worker_count) do
      CrossWorkerQueue.new
    end
  end

  def enqueue_at(from_worker_id : Int32, target_node_id : UInt32, process_at : UInt64, payload : Float64) : Void
    if process_at <= @clock.current_time
      raise RuntimeError.new("Clock time #{@clock.current_time}: Cannot enqueue an event with time #{process_at}")
    end
    @incoming_queues[from_worker_id].push(Event.new(target_node_id, process_at, payload))
  end

  # Drain all incoming queues into this worker's clock.
  def drain_all_incoming : Void
    @incoming_queues.each(&.drain_into(@clock))
  end

  def reset
    @clock.reset(0)
  end
end
