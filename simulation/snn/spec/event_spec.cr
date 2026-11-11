require "spec"
require "../src/event"

describe Event do
  it "initializes with floating-point payloads" do
    event = Event(Float64).new(4096_u16, 90_000_u32, 1000_u64, 0.75_f64)
    event.payload.should eq 0.75_f64
  end

  it "initializes with labelled tuple payloads" do
    event = Event.new(1_u32, 1_u16, 200_u64, {0.75_f64, 1_u8})
    event.payload[0].should eq 0.75
    event.payload[1].should eq 1
  end

  it "addresses a destination-local node and an incoming route" do
    event = Event(UInt64).new(4096_u16, 90_000_u32, 1000_u64, 42_u64)
    event.target_local_node_index.should eq(4096_u16)
    event.arrival_backward_route_index.should eq(90_000_u32)
    event.scheduled_time.should eq(1000_u64)
    event.payload.should eq(42_u64)
  end

  it "distinguishes external input from incoming route zero" do
    Event(UInt64).new(4096_u16, nil, 1000_u64, 42_u64).arrival_backward_route_index.should be_nil
    Event(UInt64).new(4096_u16, 0_u32, 1000_u64, 42_u64).arrival_backward_route_index.should eq 0
  end

  it "supports Bool, integer, and floating payloads without implicit conversion" do
    Event(Bool).new(0_u16, nil, 0_u64, false).payload.should be_false
    Event(UInt64).new(0_u16, nil, 0_u64, UInt64::MAX).payload.should eq(UInt64::MAX)
    Event(Float64).new(0_u16, nil, 0_u64, 0.125).payload.should eq(0.125)
  end

end
