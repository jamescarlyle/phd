require "spec"
require "../src/node/base_node"
require "../src/node/accumulator_node"
require "../src/node/lif_node"

describe AccumulatorNode do
  it "initializes with default accumulation and zero processed count" do
    node = AccumulatorNode.new(1_u32)
    node.node_id.should eq(1_u32)
    node.accumulation.should eq(0)
    node.processed_count.should eq(0_u64)
  end

  it "allows custom initial accumulation values" do
    node = AccumulatorNode.new(2_u32, 10)
    node.accumulation.should eq(10)
  end

  it "accumulates payloads, updates counts, and returns the new accumulation" do
    node = AccumulatorNode.new(3_u32, 5)
    event = Event(UInt64).new(target_local_node_idx: 0, payload: 10, scheduled_time: 50_u64)

    result = node.process(event)
    result.should eq(15)
    node.accumulation.should eq(15)
    node.processed_count.should eq(1_u64)
  end
end

describe LIFNode do
  it "initializes with default potential and update times" do
    node = LIFNode.new(1_u32)
    node.node_id.should eq(1_u32)
    node.potential.should eq(0.0)
  end

  it "ignores events where scheduled_time is less than or equal to last_update_time" do
    node = LIFNode.new(1_u32, 0.5, 100_u64)
    event = Event(Tuple(UInt8, Float64)).new(target_local_node_idx: 0_u32, payload: {1_u8, 2.0}, scheduled_time: 50_u64)

    node.process(event).should eq({1, false})
    node.potential.should eq(0.5)
  end

  it "doesn't decay potential if the event is the same time as previous" do
    node = LIFNode.new(1_u32, 0.5, 100_u64)
    event = Event(Tuple(UInt8, Float64)).new(target_local_node_idx: 0_u32, payload: {1_u8, 0.1}, scheduled_time: 100_u64)

    result = node.process(event)
    result.should eq({1, false})
    node.potential.should be_close(0.6, 0.0001)
  end

  it "decays potential over time and adds payload without spiking if below threshold" do
    node = LIFNode.new(1_u32, 0.5, 0_u64)
    event = Event(Tuple(UInt8, Float64)).new(target_local_node_idx: 0_u32, payload: {1_u8, 0.1}, scheduled_time: 10_000_u64)

    result = node.process(event)
    result.should eq({1, false})
    node.potential.should be_close(0.2839, 0.0001)
  end

  it "spikes, resets potential to V_RESET, and returns true when potential exceeds V_THRESHOLD" do
    node = LIFNode.new(0_u32, 0.0, 0_u64)
    event = Event(Tuple(UInt8, Float64)).new(target_local_node_idx: 0_u32, scheduled_time: 0_u64, payload: {1_u8, 1.5})

    result = node.process(event)
    result.should eq({1, true})
    node.potential.should eq(V_RESET)
  end
end

describe Node do
  it "manages routes properly through inheritance" do
    node = AccumulatorNode.new(1_u32)
    route = TargetRoute.new(0, 0)

    node.target_routes.should be_empty
    node.add_target_route(route)
    node.target_routes.size.should eq(1)
  end
end
