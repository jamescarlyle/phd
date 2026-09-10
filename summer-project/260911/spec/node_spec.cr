require "spec"
require "../src/node"

describe Node do
  it "initializes with its id and layer index" do
    node = Node.new(42_u32, 3)

    node.id.should eq 42_u32
    node.layer_index.should eq 3
  end

  it "initializes its state to zero" do
    node = Node.new(1_u32, 0)

    node.processed_count.should eq 0_u64
    node.state_accumulator.should eq 0.0
  end

  it "increments the processed count when processing a payload" do
    node = Node.new(1_u32, 0)

    node.process(10.0)
    node.process(20.0)

    node.processed_count.should eq 2_u64
  end

  it "updates the state accumulator using the weighted payload" do
    node = Node.new(1_u32, 0)

    result = node.process(10.0)

    result.should be_close(0.5, 1e-12)
    node.state_accumulator.should be_close(0.5, 1e-12)
  end

  it "applies the recurrence across multiple payloads" do
    node = Node.new(1_u32, 0)

    node.process(10.0)
    result = node.process(20.0)

    expected = (0.5 * 0.95) + (20.0 * 0.05)
    result.should be_close(expected, 1e-12)
    node.state_accumulator.should be_close(expected, 1e-12)
  end

  it "handles negative and fractional payloads" do
    node = Node.new(1_u32, -2)

    result = node.process(-4.5)

    result.should be_close(-0.225, 1e-12)
    node.processed_count.should eq 1_u64
  end

  it "allows the public state properties to be assigned" do
    node = Node.new(1_u32, 0)

    node.processed_count = 7_u64
    node.state_accumulator = 2.5

    node.processed_count.should eq 7_u64
    node.state_accumulator.should eq 2.5
  end
end
