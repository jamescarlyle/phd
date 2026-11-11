require "spec"
require "../src/constant"
require "../src/sync_manager"

describe WorkerState do
  it "starts at zero" do
    state = WorkerState.new
    state.next_tick.should eq 0_u64
    state.active?.should be_false
  end

  it "allows its atomic clock to be updated" do
    state = WorkerState.new
    state.next_tick=(17_u64)
    state.next_tick.should eq 17_u64
  end

  it "allow its active state to be updated" do
    state = WorkerState.new
    state.active?.should be_false
    state.active=(true)
    state.active?.should be_true
  end
end

describe SyncManager do

  describe "#initialize" do
    it "rejects invalid worker, latency, and drift configurations" do
      expect_raises(ArgumentError) { SyncManager.new(0_u32, 10_u64, 9_u64) }
      expect_raises(ArgumentError) { SyncManager.new(9_u32, 10_u64, 9_u64) }
      expect_raises(ArgumentError) { SyncManager.new(2_u32, 0_u64, 0_u64) }
      expect_raises(ArgumentError) { SyncManager.new(2_u32, 10_u64, 0_u64) }
      expect_raises(ArgumentError) { SyncManager.new(2_u32, 10_u64, 11_u64) }
    end

    it "checks worker IDs and reset interval ordering" do
      mgr = SyncManager.new(2_u32, 10_u64, 9_u64)
      expect_raises(IndexError) { mgr.worker_next_tick(2_u32) }
      expect_raises(IndexError) { mgr.record_progress(2_u32, 1_u64) }
      expect_raises(ArgumentError) { mgr.reset(10_u64, 9_u64) }
    end

    it "limits a worker to its own latency and peer progress plus drift" do
      mgr = SyncManager.new(2_u32, 10_u64, 9_u64)
      mgr.reset(0_u64, 100_u64)
      mgr.horizon_next_tick(0_u32).should eq(9_u64)
      mgr.record_progress(0_u32, 9_u64)
      mgr.horizon_next_tick(0_u32).should eq(9_u64)
      mgr.horizon_next_tick(1_u32).should eq(10_u64)
      mgr.record_progress(1_u32, 10_u64)
      mgr.horizon_next_tick(0_u32).should eq(19_u64)
    end

    it "initialises all clocks to 0" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.worker_count.times do |idx|
        sync_mgr.worker_next_tick(idx).should eq(0_u64)
      end
    end
  end

  describe "#reset" do
    it "allows drift equal to the minimum latency" do
      mgr = SyncManager.new(2_u32, 10_u64, 10_u64)
      mgr.reset(0_u64, 100_u64)
      mgr.horizon_next_tick(0_u32).should eq(10_u64)
    end

    it "caps the horizon at the exclusive finish time" do
      mgr = SyncManager.new(1_u32, 10_u64, 9_u64)
      mgr.reset(5_u64, 12_u64)
      mgr.horizon_next_tick(0_u32).should eq(12_u64)
    end

    it "saturates horizon arithmetic rather than overflowing UInt64" do
      mgr = SyncManager.new(2_u32, 10_u64, 9_u64)
      mgr.reset(UInt64::MAX - 3_u64, UInt64::MAX)
      mgr.horizon_next_tick(0_u32).should eq(UInt64::MAX)
    end

  end

  describe "#record_progress" do
    it "publishes the reported time to that worker clock" do
      sync_mgr = SyncManager.new(2_u32)
      sync_mgr.record_progress(0_u32, 42_u64)
      sync_mgr.worker_next_tick(0_u32).should eq(42_u64)
      sync_mgr.worker_next_tick(1_u32).should eq(0_u64)
    end

    it "marks a worker done after last_event_time" do
      sync_mgr = SyncManager.new(1_u32)
      sync_mgr.reset(10, 100)
      sync_mgr.worker_active?(0_u32).should be_true
      sync_mgr.record_progress(0_u32, 150_u64)
      sync_mgr.worker_active?(0_u32).should be_false
    end

    it "publishes completion only at the finish bound and can restart" do
      mgr = SyncManager.new(1_u32, 10_u64, 9_u64)
      mgr.reset(0_u64, 20_u64)
      mgr.record_progress(0_u32, 19_u64)
      mgr.worker_active?(0_u32).should be_true
      mgr.record_progress(0_u32, 20_u64)
      mgr.worker_active?(0_u32).should be_false
      mgr.reset(3_u64, 30_u64)
      mgr.worker_active?(0_u32).should be_true
      mgr.worker_next_tick(0_u32).should eq(3_u64)
    end

    it "rejects progress regression without changing stored progress" do
      mgr = SyncManager.new(1_u32, 10_u64, 9_u64)
      mgr.reset(0_u64, 100_u64)
      mgr.record_progress(0_u32, 10_u64)
      expect_raises(ArgumentError) { mgr.record_progress(0_u32, 9_u64) }
      mgr.worker_next_tick(0_u32).should eq(10_u64)
    end

    it "tests collective progress and ignores completed workers" do
      mgr = SyncManager.new(2_u32, 10_u64, 9_u64)
      mgr.reset(0_u64, 10_u64)
      mgr.all_workers_at_time?(1_u64).should be_false
      mgr.record_progress(0_u32, 10_u64)
      mgr.record_progress(1_u32, 3_u64)
      mgr.all_workers_at_time?(3_u64).should be_true
      mgr.all_workers_at_time?(4_u64).should be_false
    end
  end

  describe "#all_workers_at_time?" do
    it "returns true when all active workers are exactly at the target" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.all_workers_at_time?(50_u64).should be_true
    end

    it "returns true when all active workers are beyond the target" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_next_tick(i, 80_u64 + i) }
      sync_mgr.all_workers_at_time?(50_u64).should be_true
    end

    it "returns false when one active worker is behind the target" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.set_worker_next_tick(2, 49)
      sync_mgr.all_workers_at_time?(50_u64).should be_false
    end

    it "returns false when the first worker is behind" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.set_worker_next_tick(0, 10)
      sync_mgr.all_workers_at_time?(50_u64).should be_false
    end

    it "returns false when the last checked worker is behind" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.set_worker_next_tick(2, 10)
      sync_mgr.all_workers_at_time?(50_u64).should be_false
    end

    it "ignores inactive workers that are behind the target" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.set_worker_next_tick(1, 40)
      sync_mgr.set_worker_active(1, false)
      sync_mgr.all_workers_at_time?(50_u64).should be_true
    end

    it "returns true when every worker is inactive" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, false) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.all_workers_at_time?(999_u64).should be_true
    end

    it "treats a target of zero as always satisfied" do
      sync_mgr = SyncManager.new(3)
      3_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 50) }
      sync_mgr.all_workers_at_time?(0_u64).should be_true
    end

    it "handles targets near UInt64::MAX" do
      sync_mgr = SyncManager.new(2)
      2_u32.times { |i| sync_mgr.set_worker_active(i, true) }
      sync_mgr.set_worker_next_tick(0, UInt64::MAX)
      sync_mgr.set_worker_next_tick(1, UInt64::MAX - 1)
      sync_mgr.all_workers_at_time?(UInt64::MAX).should be_false
      sync_mgr.set_worker_next_tick(1, UInt64::MAX)
      sync_mgr.all_workers_at_time?(UInt64::MAX).should be_true
    end

    it "sees updates made after the first call" do
      sync_mgr = SyncManager.new(2)
      2_u32.times { |i| sync_mgr.set_worker_active(i, true) ; sync_mgr.set_worker_next_tick(i, 10_u64) }
      sync_mgr.all_workers_at_time?(20_u64).should be_false
      2_u32.times { |i| sync_mgr.set_worker_next_tick(i, 20_u64) }
      sync_mgr.all_workers_at_time?(20_u64).should be_true
    end
  end

  describe "#horizon_next_tick" do
    it "returns the minimum peer tick plus MAX_DRIFT" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(3, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(10, 1_000_000)
      sync_mgr.set_worker_next_tick(0, 100)
      sync_mgr.set_worker_next_tick(1, 300)
      sync_mgr.set_worker_next_tick(2, 200)
      sync_mgr.horizon_next_tick(0).should eq(200_u64 + max_drift)
    end

    it "excludes the calling worker from the minimum" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(3, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(10, 1_000_000)
      sync_mgr.set_worker_next_tick(0, 1)
      sync_mgr.set_worker_next_tick(1, 500)
      sync_mgr.set_worker_next_tick(2, 600)
      sync_mgr.horizon_next_tick(0).should eq(500_u64 + max_drift)
    end
  end

  describe "set_worker_next_tick" do
    it "updates stored atomics without changing other workers" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.max_drift.should eq(MAX_DRIFT)

      sync_mgr.worker_active?(0).should be_false
      sync_mgr.set_worker_active(0, true)
      sync_mgr.worker_active?(0).should be_true
      sync_mgr.worker_active?(1).should be_false

      sync_mgr.set_worker_next_tick(0, 123_u64)
      sync_mgr.worker_next_tick(0).should eq(123_u64)
      sync_mgr.worker_next_tick(1).should eq(0_u64)

      sync_mgr.set_worker_active(0, false)
      sync_mgr.worker_active?(0).should be_false
      sync_mgr.worker_next_tick(0).should eq(123_u64)

      sync_mgr.set_worker_active(2, true)
      sync_mgr.worker_active?(2).should be_true
    end

    it "uses the slowest peer when the caller is the fastest" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.reset(10, 1_000_000)
      sync_mgr.set_worker_next_tick(0, 900)
      sync_mgr.set_worker_next_tick(1, 100)
      sync_mgr.set_worker_next_tick(2, 400)
      sync_mgr.horizon_next_tick(0_u32).should eq(100_u64 + MAX_DRIFT)
    end

    it "includes inactive peers in the minimum" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.reset(10, 1_000_000)
      sync_mgr.set_worker_next_tick(0, 500)
      sync_mgr.set_worker_active(1, false)
      sync_mgr.set_worker_next_tick(1, 5)
      sync_mgr.set_worker_next_tick(2, 700)
      sync_mgr.horizon_next_tick(0).should eq(5_u64 + MAX_DRIFT)
    end

    it "clamps the result to end_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(10, 50)
      sync_mgr.set_worker_next_tick(0, 100)
      sync_mgr.set_worker_next_tick(1, 100)
      sync_mgr.horizon_next_tick(0).should eq(50)
    end

    it "returns end_time when the peer tick equals end_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(10, 50)
      sync_mgr.set_worker_next_tick(1, 50)
      sync_mgr.horizon_next_tick(0).should eq(50)
    end

    it "returns end_time when the peer tick exceeds end_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(10, 50)
      sync_mgr.set_worker_next_tick(1, 5000)
      sync_mgr.horizon_next_tick(0_u32).should eq(50)
    end

    it "returns end_time when drift exactly reaches end_time" do
      start_time = 50_u64
      end_time = 1_000_u64
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(start_time, end_time)
      sync_mgr.set_worker_next_tick(1, end_time - MAX_DRIFT)
      sync_mgr.horizon_next_tick(0).should eq(end_time)
    end

    it "returns one below end_time when drift falls one short" do
      start_time = 50_u64
      end_time = 1_000_u64
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(start_time, end_time)
      sync_mgr.set_worker_next_tick(1, end_time - MAX_DRIFT - 1)
      sync_mgr.horizon_next_tick(0_u32).should eq(end_time - 1)
    end

    it "does not overflow when a peer tick is UInt64::MAX" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.reset(UInt64::MIN, UInt64::MAX)
      sync_mgr.set_worker_next_tick(1, UInt64::MAX)
      sync_mgr.horizon_next_tick(0_u32).should eq(1000)
    end

    it "does not overflow when peer tick plus drift would exceed UInt64::MAX" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(2, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(UInt64::MAX - 100, UInt64::MAX)
      sync_mgr.worker_next_tick(0).should eq (UInt64::MAX - 100)
      sync_mgr.worker_next_tick(1).should eq (UInt64::MAX - 100)
      sync_mgr.set_worker_next_tick(1, UInt64::MAX - 1)
      sync_mgr.worker_next_tick(1).should eq (UInt64::MAX - 1)
      sync_mgr.horizon_next_tick(0_u32).should eq(UInt64::MAX)
    end

    it "returns exact tick plus drift just below UInt64::MAX" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(2, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(UInt64::MAX - 100, UInt64::MAX)
      sync_mgr.set_worker_next_tick(1, UInt64::MAX - max_drift - 1)
      sync_mgr.horizon_next_tick(0).should eq(UInt64::MAX - 1)
    end

    it "responds to peer progress between calls" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(2, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(UInt64::MIN, UInt64::MAX)
      sync_mgr.set_worker_next_tick(1, 10)
      first = sync_mgr.horizon_next_tick(0)
      sync_mgr.set_worker_next_tick(1, 20)
      sync_mgr.horizon_next_tick(0).should eq(first + 10_u64)
    end

    it "responds to a change in end_time" do
      layer_latency = 1000_u64
      max_drift = 40_u64
      sync_mgr = SyncManager.new(2, layer_latency: layer_latency, max_drift: max_drift)
      sync_mgr.reset(10, 200)
      sync_mgr.set_worker_next_tick(1, 90)
      sync_mgr.horizon_next_tick(0).should eq(130)
      sync_mgr.reset(10, 1_000_000)
      sync_mgr.worker_next_tick(1).should eq(10)
      sync_mgr.horizon_next_tick(0).should eq(10 + max_drift)
    end
  end

end
