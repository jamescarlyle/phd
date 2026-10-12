require "spec"
require "../src/network"
require "../src/type"
require "../src/node/*"
require "../src/constant"
require "../src/worker"
require "../src/event"

describe Worker do
  layer_sizes = [3_u32, 4_u32, 2_u32]
  network = AccumulatorNetwork.new(layer_sizes, MAX_WORKERS)
  describe "#layer_idx" do
    it "returns 0 for nodes in layer 0" do
      network.layer_idx(0u32).should eq(0u32)
      network.layer_idx(100u32).should eq(0u32)
      network.layer_idx(2311u32).should eq(0u32)
      network.layer_idx(4095u32).should eq(0u32)
    end

    it "returns 1 for nodes in layer 1" do
      network.layer_idx(4096u32).should eq(1u32)   # 1 * 4096
      network.layer_idx(6000u32).should eq(1u32)
      network.layer_idx(8191u32).should eq(1u32)
    end

    it "returns correct layer for higher layers" do
      network.layer_idx(8192u32).should eq(2u32)   # 2 * 4096
      network.layer_idx(12287u32).should eq(2u32)
      network.layer_idx(12288u32).should eq(3u32)  # 3 * 4096
    end
  end
end
