require "../../src/worker"

class Worker(N, P, R)
  getter scheduled_events = [] of Event(P)

  def schedule(source_global_node_index : UInt32, target_node_index : UInt16, process_at : UInt64, payload : P) : Void
    @scheduled_events << Event(P).new(source_global_node_index, target_node_index, process_at, payload)

    previous_def
  end
end
