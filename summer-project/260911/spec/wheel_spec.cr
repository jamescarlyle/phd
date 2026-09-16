require "spec"
require "../src/wheel"

event_1 = Event.new(1_u32, 1_u64, 2.5)
event_2 = Event.new(2_u32, 10_u64, -1.0)
event_3 = Event.new(1_u32, 65_540_u64, 65_540.0)
event_4 = Event.new(1_u32, 16_777_220_u64, 16_777_220.0)

describe HierarchicalWheel do
  describe "basic scheduling" do
    it "fires a zero-delay event on the current tick" do
      wheel = HierarchicalWheel.new(1_u64)
      fired = Array(Event).new

      wheel.schedule(event_1)
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].target_node.should eq(1_u32)
      fired[0].process_at.should eq(1_u64)
      fired[0].payload.should eq(2.5)
      wheel.current_time.should eq(2_u64)
    end

    it "fires a one-tick-delay event on the next tick" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(event_1)
      wheel.tick { }
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].target_node.should eq(1_u32)
      fired[0].process_at.should eq(1_u64)
      wheel.current_time.should eq(2_u64)
    end
  end

  describe "current_time semantics" do
    it "treats current_time as the tick currently processed" do
      wheel = HierarchicalWheel.new(5_u64)
      fired = Array(Event).new

      wheel.schedule(Event.new(10_u32, 5_u64, 5.5))
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(5_u64)
      wheel.current_time.should eq(6_u64)
    end

    it "does not fire an event scheduled for a future tick" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(Event.new(10_u32, 5_u64, 5.5))
      5.times { wheel.tick { |event| fired << event } }

      fired.size.should eq(0)
      wheel.current_time.should eq(5_u64)

      wheel.tick { |event| fired << event }
      fired.size.should eq(1)
      fired[0].process_at.should eq(5_u64)
      wheel.current_time.should eq(6_u64)
    end
  end

  describe "tier promotion" do
    it "promotes an event from tier 2" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(Event.new(1_u32, 260_u64, 260.0))
      260.times { wheel.tick { } }
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(260_u64)
    end

    it "promotes an event from tier 3" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(event_3)
      65_540.times { wheel.tick { } }
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(65_540_u64)
    end

    it "promotes an event from tier 4" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(event_4)
      16_777_220.times { wheel.tick { } }
      wheel.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(16_777_220_u64)
    end
  end

  describe "multiple events" do
    it "fires multiple events scheduled for the same tick" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(Event.new(1_u32, 0_u64, 1.0))
      wheel.schedule(Event.new(2_u32, 0_u64, 2.0))
      wheel.schedule(Event.new(3_u32, 0_u64, 3.0))
      wheel.tick { |event| fired << event }

      fired.size.should eq(3)
      fired.map(&.target_node).sort!.should eq([1_u32, 2_u32, 3_u32])
    end

    it "fires events in ascending expiry order within a tick" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      # These three events have the same expiry tick. Their insertion order
      # is the deterministic order expected from the wheel.
      wheel.schedule(Event.new(1_u32, 10_u64, 10.0))
      wheel.schedule(Event.new(2_u32, 10_u64, 10.1))
      wheel.schedule(Event.new(3_u32, 10_u64, 10.2))

      11.times { wheel.tick { |event| fired << event } }

      fired.size.should eq(3)
      fired.map(&.process_at).should eq([10_u64, 10_u64, 10_u64])
      fired.map(&.target_node).should eq([1_u32, 2_u32, 3_u32])
    end
  end

  describe "advance_to" do
    it "processes every tick through target_time inclusively" do
      wheel = HierarchicalWheel.new(0_u64)
      fired = Array(Event).new

      wheel.schedule(event_1)
      wheel.schedule(event_2)
      wheel.advance_to(10_u64) { |event| fired << event }

      fired.size.should eq(2)
      fired.map(&.target_node).should eq([1_u32, 2_u32])
      wheel.current_time.should eq(11_u64)
    end

    it "raises when target_time is before current_time" do
      wheel = HierarchicalWheel.new(10_u64)
      expect_raises(RuntimeError, "Cannot move backwards") do
        wheel.advance_to(5_u64) { }
      end
    end
  end

  describe "validation" do
    it "rejects a delay larger than MAX_DELAY" do
      wheel = HierarchicalWheel.new(0_u64)
      expect_raises(RuntimeError, "Delay exceeds wheel capacity") do
        wheel.schedule(1_u32, HierarchicalWheel::MAX_DELAY + 1_u64)
      end
    end
  end
end
