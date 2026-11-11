require "../../src/worker"

class Worker(N, P, R)
  getter scheduled_events = [] of Event(P)

  def schedule(target_local_index : UInt16, arrival_backward_route_index : UInt32?, target_time : UInt64, payload : P) : Bool
    @scheduled_events << Event(P).new(target_local_index, arrival_backward_route_index, target_time, payload)

    previous_def
  end
end
