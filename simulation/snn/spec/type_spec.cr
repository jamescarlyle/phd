require "spec"
require "../src/type"
require "../src/event"

describe "Compile-Time Type Configuration" do
  {% if flag?(:node_lif) %}
    it "binds ActiveNode to LIFNode under -Dnode_lif" do
      ActiveNode.should eq(LIFNode)
      ActivePayload.should eq(Float64)
      ActiveReturn.should eq(Bool)
    end

    it "instantiates ActiveNode as a subtype of Node(Float64, Bool)" do
      node = ActiveNode.new(101_u32)
      node.should be_a(Node(Float64, Bool))
      node.node_id.should eq(101_u32)
    end

    it "processes events and returns an ActiveReturn boolean" do
      node = ActiveNode.new(101_u32)
      event = Event(ActivePayload).new(0_u32, 100_u64, 0.5_f64)
      result = node.process(event)
      result.should be_a(ActiveReturn)
      result.should be_false
    end
  {% else %}
    it "binds ActiveNode to AccumulatorNode by default" do
      ActiveNode.should eq(AccumulatorNode)
      ActivePayload.should eq(UInt64)
      ActiveReturn.should eq(UInt64)
    end

    it "instantiates ActiveNode as a subtype of Node(UInt64, UInt64)" do
      node = ActiveNode.new(202_u32)
      node.should be_a(Node(UInt64, UInt64))
      node.node_id.should eq(202_u32)
    end

    it "processes events and returns an ActiveReturn unsigned integer" do
      node = ActiveNode.new(202_u32)
      event = Event(ActivePayload).new(0_u32, 50_u64, 42_u64)
      result = node.process(event)
      result.should be_a(ActiveReturn)
      result.should eq(42_u64)
    end
  {% end %}

  it "verifies route addition capabilities on the active node" do
    node = ActiveNode.new(1_u32)
    route = TargetRoute.new(0_u32, 10_u32)
    node.add_target_route(route)
    node.target_routes.size.should eq(1)
    node.target_routes.first.target_worker_id.should eq(0_u32)
  end
end
