require "spec"
require "../src/constant"
require "../src/network"
require "../src/worker"

def find_global_node_index(
  network : AccumulatorNetwork,
  worker_id : UInt8,
  worker_local_node_index : UInt16
) : UInt32?
  network.total_node_count.times do |global_node_index|
    allocation = network.node_allocation(global_node_index)

    if allocation.worker_id == worker_id &&
       allocation.worker_local_node_index == worker_local_node_index
      return global_node_index
    end
  end

  nil
end

describe Worker do
  describe "with a worker owning two nodes and three weights" do
    network = AccumulatorNetwork.new([4_u16, 3_u16, 2_u16], 8_u8, 0.0)
    worker = network.workers[0]

    it "initialises all node states to zero" do
      worker.nodes.to_a.each do |node|
        node.accumulation.should eq(0.0)
      end
    end

    it "initialises all weights to the requested value" do
      worker.weight_values.to_a.each do |weight_value|
        weight_value.should eq(0.0)
      end
    end

    it "reads and writes a weight value" do
      worker.set_weight_value(0_u32, 1.5)

      worker.weight_value(0_u32).should eq(1.5)
    end

    it "adds to a weight value" do
      worker.set_weight_value(1_u32, 2.0)
      worker.add_to_weight_value(1_u32, 0.25)

      worker.weight_value(1_u32).should eq(2.25)
    end

    it "resets node states" do
      node = worker.node(0_u16)
      node.process(Event.new(0_u32, 0_u16, 0_u64, 0_u64))
      worker.node(0_u16).processed_count.should eq(1)

      worker.reset_nodes

      worker.node(0_u16).processed_count.should eq(0)
    end

    it "resets weight values" do
      worker.set_weight_value(2_u32, 9.0)

      worker.reset_weight_values

      worker.weight_value(2_u32).should eq(0.0)
    end

    it "iterates backward routes with their worker-local weights" do
      layer_one_first_global_index = network.layer_offsets[1]

      route_count = 0_u32

      worker.each_backward_route(layer_one_first_global_index) do |route, weight_value, weight_index|
        route.should be_a(BackwardRoute)
        weight_value.should eq(0.0)
        weight_index.should be < worker.weight_count

        route_count += 1_u32
      end

      route_count.should eq(4_u32)
    end
  end
end
