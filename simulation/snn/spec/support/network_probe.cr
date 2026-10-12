require "../../src/network"

class Network
  def workers_for_spec : Array(Worker(N, P, R))
    @workers
  end
end
