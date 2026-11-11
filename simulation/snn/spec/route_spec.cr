require "spec"
require "../src/route"

describe ForwardRoute do
  it "distinguishes parallel edges between the same endpoints" do
    a = ForwardRoute.new(1_u8, 4_u16, 8_u32)
    b = ForwardRoute.new(1_u8, 4_u16, 9_u32)
    a.target_key.should eq(b.target_key)
    a.target_backward_route_index.should_not eq(b.target_backward_route_index)
  end

  it "identifies the peer node and its worker-local incoming route slot" do
    route = ForwardRoute.new(2_u8, 4000_u16, 80_000_u32)
    route.target_worker_id.should eq(2_u8)
    route.target_worker_local_node_index.should eq(4000_u16)
    route.target_backward_route_index.should eq(80_000_u32)
    route.target_key.should eq(NodeKey.new(2_u8, 4000_u16))
  end

  it "distinguishes parallel edges between the same endpoints" do
    a = ForwardRoute.new(1_u8, 4_u16, 8_u32)
    b = ForwardRoute.new(1_u8, 4_u16, 9_u32)
    a.target_key.should eq(b.target_key)
    a.target_backward_route_index.should_not eq(b.target_backward_route_index)
  end
end

describe BackwardRoute do
  it "keeps source identity, reciprocal outgoing slot, and local weight slot separate" do
    route = BackwardRoute.new(3_u8, 12_u16, 90_000_u32, 7_u32)
    route.source_key.should eq(NodeKey.new(3_u8, 12_u16))
    route.source_forward_route_index.should eq(90_000_u32)
    route.worker_local_weight_index.should eq(7_u32)
  end

  it "permits two incoming edges from one source with different route identities" do
    a = BackwardRoute.new(0_u8, 0_u16, 2_u32, 10_u32)
    b = BackwardRoute.new(0_u8, 0_u16, 3_u32, 11_u32)
    a.source_key.should eq(b.source_key)
    a.source_forward_route_index.should_not eq(b.source_forward_route_index)
    a.worker_local_weight_index.should_not eq(b.worker_local_weight_index)
  end
end
