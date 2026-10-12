require "../../src/worker"

class Worker(N, P, R)
  getter scheduled_events = [] of Event(P)

  def schedule(target_node_id : UInt32, process_at : UInt64, payload : P) : Void
    @scheduled_events << Event(P).new(target_node_id, process_at, payload)

    previous_def
  end
end
