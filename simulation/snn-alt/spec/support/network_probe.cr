require "../../src/network"

class Network
  def workers_for_spec : Slice(Worker(N, P, R))
    @workers
  end
end
