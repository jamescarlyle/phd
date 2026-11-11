require "spec"
require "../src/node/base_node"
require "../src/node/accumulator_node"
require "../src/node/lif_node"

describe AccumulatorNode do
  it "initializes with default accumulation and zero processed count" do
    node = AccumulatorNode.new()
    node.accumulation.should eq(0)
    node.processed_count.should eq(0_u64)
  end

  it "allows custom initial accumulation values" do
    node = AccumulatorNode.new(10)
    node.accumulation.should eq(10)
  end

  it "accumulates payloads, updates counts, and returns the new accumulation" do
    node = AccumulatorNode.new(5)
    event = Event(UInt64).new(target_local_node_index: 0_u16, arrival_backward_route_index: 0_u32, scheduled_time: 50_u64, payload: 10)

    result = node.process(event)
    result.should eq(15)
    node.accumulation.should eq(15)
    node.processed_count.should eq(1_u64)
  end

  it "clears accumulation and count and is reusable after reset" do
    node = AccumulatorNode.new
    node.process(Event(UInt64).new(0_u16, 0_u32, 50_u64, 12_u64))
    node.reset
    node.accumulation.should eq(0_u64)
    node.processed_count.should eq(0_u64)
    node.process(Event(UInt64).new(0_u16, 0_u32, 50_u64, 2_u64)).should eq(2_u64)
    node.processed_count.should eq(1_u64)
  end
end

describe LIFNode do
  it "initializes with default potential and update times" do
    node = LIFNode.new
    node.potential.should eq(V_REST)
    node.responds_to?(:node_id).should be_false
  end

  it "ignores older timestamps without altering membrane state" do
    node = LIFNode.new
    node.process(Event(Float64).new(0_u16, nil, 10_u64, 0.5))
    node.process(Event(Float64).new(0_u16, nil, 9_u64, 100.0)).should be_false
    node.potential.should eq(0.5)
  end

  it "doesn't decay potential if the event is the same time as previous" do
    node = LIFNode.new(potential: 0.5_f64, last_update_time: 100_u64)
    event = Event(Float64).new(0_u16, nil, 100_u64, 0.1_f64)
    result = node.process(event)
    result.should be_false
    node.potential.should be_close(0.6, 0.0001)
  end

  it "decays potential over time and adds payload without spiking if below threshold" do
    node = LIFNode.new
    node.process(Event(Float64).new(0_u16, nil, 0_u64, 0.5)).should be_false
    node.process(Event(Float64).new(0_u16, nil, 10_000_u64, 0.0)).should be_false
    node.potential.should be_close(0.5 * Math.exp(-1.0), 1e-12)
  end

  it "retains the existing strict threshold and reset voltage" do
    node = LIFNode.new
    node.process(Event(Float64).new(0_u16, nil, 0_u64, 1.0)).should be_false
    node.process(Event(Float64).new(0_u16, 0_u32, 0_u64, 0.1)).should be_true
    node.potential.should eq(V_RESET)
  end

  it "spikes, resets potential to V_RESET, and returns true when potential exceeds V_THRESHOLD" do
    node = LIFNode.new
    event = Event(Float64).new(target_local_node_index: 0_u16, arrival_backward_route_index: 0_u32, scheduled_time: 0_u64, payload: 1.5)

    result = node.process(event)
    result.should be_true
    node.potential.should eq(V_RESET)
  end

  it "clears potential and count and is reusable after reset" do
    node = LIFNode.new
    node.process(Event(Float64).new(0_u16, 0_u32, 50_u64, 12_u64))
    node.reset
    node.potential.should eq(0_f64)
    node.last_update_time.should eq(0_u64)
  end
end
