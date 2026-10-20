require "spec"
require "../src/event"

describe Event do
  it "initializes with the supplied fields" do
    event = Event.new(42_u32, 42_u16, 123_u64, 35_u64)
    event.source_global_node_index.should eq 42_u32
    event.target_local_node_index.should eq 42_u16
    event.scheduled_time.should eq 123_u64
    event.payload.should eq 35
  end

  it "initializes with floating-point payloads" do
    event = Event.new(1_u32, 1_u16, 200_u64, 0.75_f64)
    event.payload.should eq 0.75_f64
  end

  it "initializes with labelled payloads" do
    event = Event.new(1_u32, 1_u16, 200_u64, {0.75_f64, 1_u8})
    event.payload[0].should eq 0.75
    event.payload[1].should eq 1
  end

end
