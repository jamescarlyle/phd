require "spec"
require "../src/event"

describe Event do
  it "initializes with the supplied fields" do
    event = Event.new(42_u32, 123_u64, 35_u64)
    event.target_local_node_idx.should eq 42_u32
    event.scheduled_time.should eq 123_u64
    event.payload.should eq 35
  end

  it "initializes with floating-point payloads" do
    event = Event.new(1_u32, 200_u64, 0.75_f64)
    event.payload.should eq 0.75_f64
  end
end
