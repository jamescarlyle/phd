require "spec"
require "../src/hierarchical_clock"

event_1 = Event.new(1_u32, 1_u64, 2.5)
event_2 = Event.new(2_u32, 10_u64, -1.0)
event_3 = Event.new(1_u32, 65_540_u64, 65_540.0)
event_4 = Event.new(1_u32, 16_777_220_u64, 16_777_220.0)

describe HierarchicalClock do
  describe "basic scheduling" do
    it "fires a zero-delay event on the current tick" do
      clock = HierarchicalClock.new(1_u64)
      fired = Array(Event).new

      clock.schedule(event_1)
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].target_node.should eq(1_u32)
      fired[0].process_at.should eq(1_u64)
      fired[0].payload.should eq(2.5)
      clock.current_time.should eq(2_u64)
    end

    it "fires a one-tick-delay event on the next tick" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(event_1)
      clock.tick { }
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].target_node.should eq(1_u32)
      fired[0].process_at.should eq(1_u64)
      clock.current_time.should eq(2_u64)
    end
  end

  describe "current_time semantics" do
    it "treats current_time as the tick currently processed" do
      clock = HierarchicalClock.new(5_u64)
      fired = Array(Event).new

      clock.schedule(Event.new(10_u32, 5_u64, 5.5))
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(5_u64)
      clock.current_time.should eq(6_u64)
    end

    it "does not fire an event scheduled for a future tick" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(Event.new(10_u32, 5_u64, 5.5))
      5.times { clock.tick { |event| fired << event } }

      fired.size.should eq(0)
      clock.current_time.should eq(5_u64)

      clock.tick { |event| fired << event }
      fired.size.should eq(1)
      fired[0].process_at.should eq(5_u64)
      clock.current_time.should eq(6_u64)
    end
  end

  describe "tier promotion" do
    it "promotes an event from tier 2" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(Event.new(1_u32, 260_u64, 260.0))
      260.times { clock.tick { } }
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(260_u64)
    end

    it "promotes an event from tier 3" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(event_3)
      65_540.times { clock.tick { } }
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(65_540_u64)
    end

    it "promotes an event from tier 4" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(event_4)
      16_777_220.times { clock.tick { } }
      clock.tick { |event| fired << event }

      fired.size.should eq(1)
      fired[0].process_at.should eq(16_777_220_u64)
    end
  end

  describe "multiple events" do
    it "fires multiple events scheduled for the same tick" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(Event.new(1_u32, 0_u64, 1.0))
      clock.schedule(Event.new(2_u32, 0_u64, 2.0))
      clock.schedule(Event.new(3_u32, 0_u64, 3.0))
      clock.tick { |event| fired << event }

      fired.size.should eq(3)
      fired.map(&.target_node).sort!.should eq([1_u32, 2_u32, 3_u32])
    end

    it "fires events in ascending expiry order within a tick" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      # These three events have the same expiry tick. Their insertion order
      # is the deterministic order expected from the clock.
      clock.schedule(Event.new(1_u32, 10_u64, 10.0))
      clock.schedule(Event.new(2_u32, 10_u64, 10.1))
      clock.schedule(Event.new(3_u32, 10_u64, 10.2))

      11.times { clock.tick { |event| fired << event } }

      fired.size.should eq(3)
      fired.map(&.process_at).should eq([10_u64, 10_u64, 10_u64])
      fired.map(&.target_node).should eq([1_u32, 2_u32, 3_u32])
    end
  end

  describe "advance_to" do
    it "processes every tick through target_time inclusively" do
      clock = HierarchicalClock.new(0_u64)
      fired = Array(Event).new

      clock.schedule(event_1)
      clock.schedule(event_2)
      clock.advance_to(11_u64) { |event| fired << event }

      fired.size.should eq(2)
      fired.map(&.target_node).should eq([1_u32, 2_u32])
      clock.current_time.should eq(11_u64)
    end

    it "raises when target_time is before current_time" do
      clock = HierarchicalClock.new(10_u64)
      expect_raises(RuntimeError, "Cannot move backwards") do
        clock.advance_to(5_u64) { }
      end
    end
  end

  describe "validation" do
    it "rejects a delay larger than MAX_DELAY" do
      clock = HierarchicalClock.new(0_u64)
      expect_raises(RuntimeError, "Delay exceeds clock capacity") do
        clock.schedule(1_u32, HierarchicalClock::WHEEL_CAPACITY + 1_u64)
      end
    end
  end

  describe "reset" do
    it "resets its time to that specified" do
      clock = HierarchicalClock.new(10_u64)
      clock.reset(5_u64)
      clock.current_time.should eq(5_u64)
    end
  end

end
