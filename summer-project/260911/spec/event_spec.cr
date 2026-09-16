require "spec"
require "../src/event"

describe Event do
  it "initializes with the supplied fields" do
    event = Event.new(42_u32, 123_u64, 3.5)

    event.target_node.should eq 42_u32
    event.process_at.should eq 123_u64
    event.payload.should eq 3.5
  end

  it "provides zero-valued defaults" do
    event = Event.new

    event.target_node.should eq 0_u32
    event.process_at.should eq 0_u64
    event.payload.should eq 0.0
  end
end
