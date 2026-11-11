require "spec"
require "set"
require "../../constant"
require "../../node_key"
require "../../route"
require "../../event"
require "../../buffer"
require "../../clock"
require "../../sync_manager"
require "../../network"

if ENV["SNN_SPEC_PARALLEL"]? == "1"
  Fiber::ExecutionContext.default.resize(4)
end

class RefactorTraceNode < Node(UInt64, UInt64)
  getter events = [] of Event(UInt64)

  def initialize
    super()
  end

  def process(event : Event(UInt64)) : UInt64
    @events << event
    event.payload
  end

  def reset : Nil
    @events.clear
  end
end

class RefactorGateNode < Node(Float64, Bool)
  property emit : Bool = false
  getter events = [] of Event(Float64)

  def initialize
    super()
  end

  def process(event : Event(Float64)) : Bool
    @events << event
    @emit
  end

  def reset : Nil
    @events.clear
    @emit = false
  end
end

module RefactorSpecs
  def self.event(time = 0_u64, payload = 1_u64, target = 0_u16,
                 incoming : UInt32? = nil) : Event(UInt64)
    Event(UInt64).new(target, incoming, time, payload)
  end

  def self.network(sizes = [2_u16, 2_u16], workers = 2_u8,
                   capacity = 4, latency = 10_u64, drift = 9_u64,
                   weight = 0.0)
    Network(RefactorTraceNode, UInt64, UInt64).new(
      sizes, workers, initial_weight_value: weight,
      layer_latency: latency, max_drift: drift,
      slot_capacity: capacity, autostart: false)
  end

  def self.gate_network
    Network(RefactorGateNode, Float64, Bool).new(
      [1_u16, 1_u16], 1_u8, layer_latency: 10_u64,
      max_drift: 9_u64, slot_capacity: 4, autostart: false)
  end

  def self.node(net, layer : Int32, index : Int32)
    key = net.layer_nodes[layer][index]
    net.workers[key.worker_id].node(key.worker_local_node_index)
  end

  def self.inject(net, layer : Int32, index : Int32,
                  time : UInt64, payload : UInt64 = 1_u64) : Bool
    key = net.layer_nodes[layer][index]
    net.workers[key.worker_id].schedule(
      key.worker_local_node_index, nil, time, payload)
  end

  def self.drive(net, limit = 50_000) : Nil
    limit.times do
      return if net.workers.all?(&.completed?)
      net.workers.each(&.iterate)
    end
    raise "Worker iteration limit exceeded: deadlock or nontermination"
  end

  def self.parallel_drive(net) : Nil
    stop = Atomic(Bool).new(false)
    results = Channel(Exception?).new(net.workers.size)
    net.workers.each do |worker|
      spawn do
        error : Exception? = nil
        begin
          iterations = 0
          until stop.get || worker.completed?
            worker.iterate
            iterations += 1
            raise "Parallel worker iteration limit exceeded" if iterations > 1_000_000
            Fiber.yield
          end
        rescue ex : Exception
          error = ex
        ensure
          results.send(error)
        end
      end
    end
    begin
      net.workers.size.times do
        select
        when error = results.receive
          raise error if error
        when timeout(10.seconds)
          raise "Parallel worker timeout"
        end
      end
    ensure
      stop.set(true)
    end
  end
end
