require "spec"
require "../src/route"

describe TargetRoute do
  it "initializes correctly with UInt32 values" do
    worker_id = 1_u32
    node_idx = 5_u32

    route = TargetRoute.new(worker_id, node_idx)

    route.target_worker_id.should eq(worker_id)
    route.target_local_node_idx.should eq(node_idx)
  end
end

describe SourceRoute do
  it "initializes with default weight within range and default eligibility" do
    worker_id = 2_u32
    node_idx = 10_u32

    route = SourceRoute.new(worker_id, node_idx)

    route.weight.should be >= WEIGHT_MIN
    route.weight.should be <= WEIGHT_MAX
    route.eligibility.should eq(0.0)
  end

  it "accepts custom weight and eligibility values" do
    worker_id = 3_u32
    node_idx = 15_u32
    custom_weight = 0.15
    custom_eligibility = 1.0

    route = SourceRoute.new(
      source_worker_id: worker_id,
      source_local_node_idx: node_idx,
      weight: custom_weight,
      eligibility: custom_eligibility
    )

    route.weight.should eq(custom_weight)
    route.eligibility.should eq(custom_eligibility)
  end

  it "allows modifying weight and eligibility via properties" do
    route = SourceRoute.new(1_u32, 2_u32)

    route.weight = 0.2
    route.weight.should eq(0.2)

    route.eligibility = 0.75
    route.eligibility.should eq(0.75)
  end
end
