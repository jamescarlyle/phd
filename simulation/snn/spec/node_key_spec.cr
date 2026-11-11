require "spec"
require "../src/node_key"

describe NodeKey do
  it "stores only a worker address and its compact local index" do
    key = NodeKey.new(3_u8, 4096_u16)
    key.worker_id.should eq(3_u8)
    key.worker_local_node_index.should eq(4096_u16)
    key.responds_to?(:global_node_index).should be_false
  end

  it "has value equality and can be used as a hash key" do
    a = NodeKey.new(1_u8, 12_u16)
    b = NodeKey.new(1_u8, 12_u16)
    a.should eq(b)
    {a => 42}[b].should eq(42)
    a.should_not eq(NodeKey.new(2_u8, 12_u16))
  end

  it "round-trips the full UInt16 local-index range without worker-bit overlap" do
    (0_u8...8_u8).each do |worker|
      [0_u16, 1_u16, 4095_u16, 4096_u16, UInt16::MAX].each do |local|
        key = NodeKey.new(worker, local)
        NodeKey.from_packed_value(key.packed_value).should eq(key)
      end
    end
  end

  it "does not alias local index 4096 to the next worker" do
    NodeKey.new(0_u8, 4096_u16).packed_value.should_not eq(
      NodeKey.new(1_u8, 0_u16).packed_value)
  end

  it "rejects worker IDs outside the configured maximum" do
    expect_raises(ArgumentError) { NodeKey.new(MAX_WORKERS, 0_u16) }
  end
end
