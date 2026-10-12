require "spec"
require "../src/constants"
require "../src/sync_manager"

describe WorkerClock do
  it "starts at zero" do
    clock = WorkerClock.new

    clock.clock.get.should eq 0_u64
  end

  it "allows its atomic clock to be updated" do
    clock = WorkerClock.new

    clock.clock.set(17_u64)

    clock.clock.get.should eq 17_u64
  end
end

describe SyncManager do
  describe "#initialize" do
    it "creates worker_clocks array with correct size" do
      worker_count = 4
      sync_mgr = SyncManager.new(worker_count)
      sync_mgr.worker_clocks.size.should eq(worker_count)
    end

    it "initialises all clocks to 0" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.worker_clocks.each(&.clock.get.should eq(0_u64))
      # sync_mgr.global_min.get.should eq(0_u64)
      sync_mgr.loader_time.get.should eq(0_u64)
    end
  end

  describe "#update_loader_time" do
    it "updates loader_time atomically" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_loader_time(100_u64)
      sync_mgr.loader_time.get.should eq(100_u64)
      sync_mgr.update_loader_time(250_u64)
      sync_mgr.loader_time.get.should eq(250_u64)
    end
  end

  describe "#record_progress" do
    it "publishes the reported time to that worker clock" do
      sync_mgr = SyncManager.new(2)

      sync_mgr.record_progress(0, 42_u64)

      sync_mgr.worker_clocks[0].clock.get.should eq(42_u64)
      sync_mgr.worker_clocks[1].clock.get.should eq(0_u64)
    end

    it "advances global_min once every worker has progressed" do
      sync_mgr = SyncManager.new(2)

      sync_mgr.record_progress(0, 10_u64)
      sync_mgr.global_min.get.should eq(0_u64)

      sync_mgr.record_progress(1, 7_u64)
      sync_mgr.global_min.get.should eq(7_u64)

      sync_mgr.record_progress(1, 15_u64)
      sync_mgr.global_min.get.should eq(10_u64)
    end

    it "does not move global_min backwards" do
      sync_mgr = SyncManager.new(2)

      sync_mgr.record_progress(0, 10_u64)
      sync_mgr.record_progress(1, 10_u64)
      sync_mgr.global_min.get.should eq(10_u64)

      # Progress reports are expected to be monotonic per worker in production,
      # but global_min itself must remain monotonic.
      sync_mgr.record_progress(0, 5_u64)

      sync_mgr.global_min.get.should eq(10_u64)
    end

    it "marks a worker done at last_event_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(100_u64)

      sync_mgr.record_progress(0, 99_u64)
      sync_mgr.worker_finished_sample?(0).should be_false

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.worker_finished_sample?(0).should be_true
    end

    it "marks a worker done after last_event_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(100_u64)

      sync_mgr.record_progress(1, 150_u64)

      sync_mgr.worker_finished_sample?(1).should be_true
    end

    it "tracks completion independently for each worker" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.update_last_event_time(100_u64)

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 99_u64)
      sync_mgr.record_progress(2, 120_u64)

      sync_mgr.worker_finished_sample?(0).should be_true
      sync_mgr.worker_finished_sample?(1).should be_false
      sync_mgr.worker_finished_sample?(2).should be_true
      sync_mgr.all_workers_finished_sample?.should be_false
    end

    it "reports all workers done only after every worker reports completion" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.update_last_event_time(100_u64)

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 100_u64)
      sync_mgr.all_workers_finished_sample?.should be_false

      sync_mgr.record_progress(2, 100_u64)
      sync_mgr.all_workers_finished_sample?.should be_true
    end
  end

  describe "#safe_time" do
    it "uses loader_time as the only limit for one worker" do
      sync_mgr = SyncManager.new(1, 10_u64)
      sync_mgr.update_loader_time(500_u64)

      sync_mgr.safe_time(0).should eq(500_u64)
    end

    it "uses the slowest peer plus layer_delay" do
      sync_mgr = SyncManager.new(3, 10_u64)
      sync_mgr.update_loader_time(1_000_u64)

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 40_u64)
      sync_mgr.record_progress(2, 70_u64)

      # Worker 0 excludes itself: min(peer 1=40, peer 2=70) + 10.
      sync_mgr.safe_time(0).should eq(50_u64)

      # Worker 1 excludes itself: min(peer 0=100, peer 2=70) + 10.
      sync_mgr.safe_time(1).should eq(80_u64)
    end

    it "never returns a time later than loader_time" do
      sync_mgr = SyncManager.new(2, 10_u64)
      sync_mgr.update_loader_time(45_u64)

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 100_u64)

      sync_mgr.safe_time(0).should eq(45_u64)
      sync_mgr.safe_time(1).should eq(45_u64)
    end
  end

  it "does not update the global minimum until a worker exceeds the safe horizon" do
    manager = SyncManager.new(2)
    manager.update_loader_time(1_u64)
    manager.global_min.get.should eq 0_u64
    manager.record_progress(0, 1_u64)
    manager.record_progress(1, 1_u64)
    manager.global_min.get.should eq 1_u64
    # Now push one worker far enough to trigger recomputation
    manager.record_progress(0, 3_u64)
    manager.global_min.get.should eq 1_u64
  end

  it "allows worker to proceed when within LAYER_DELAY of global_min" do
    sync_mgr = SyncManager.new(2)
    sync_mgr.global_min.get.should eq 0_u64
    sync_mgr.update_loader_time(1_u64)
    sync_mgr.global_min.get.should eq 0_u64
    sync_mgr.record_progress(0, sync_mgr.global_min.get + LAYER_DELAY)
    sync_mgr.global_min.get.should eq 0_u64
    sync_mgr.record_progress(1, sync_mgr.global_min.get + LAYER_DELAY)
    sync_mgr.global_min.get.should eq 1_u64
    sync_mgr.worker_clocks[0].clock.get.should eq 1_u64
  end

  it "blocks worker when it exceeds loader_time + LAYER_DELAY" do
    sync_mgr = SyncManager.new(2)
    sync_mgr.update_loader_time(100_u64)

    # Worker at time 102 should be blocked (LAYER_DELAY = 1, so limit is 101)
    sync_mgr.record_progress(0, 102_u64)
  end

  it "updates global_min only when worker exceeds cached_min + LAYER_DELAY" do
    sync_mgr = SyncManager.new(2)
    sync_mgr.update_loader_time(50_u64)

    # Initially global_min is 0
    sync_mgr.global_min.get.should eq(0_u64)

    # Worker 0 advances to 50 (within LAYER_DELAY of loader_time=50)
    sync_mgr.record_progress(0, 51_u64)
    # global_min is NOT updated because worker didn't exceed cached_min + LAYER_DELAY
    sync_mgr.global_min.get.should eq(0_u64)

    # Worker 1 advances to 55
    sync_mgr.record_progress(1, 51_u64)
    sync_mgr.update_loader_time(52_u64)
    sync_mgr.record_progress(1, 52_u64)
    sync_mgr.global_min.get.should eq(51_u64)

    # Worker clocks are updated though
    sync_mgr.worker_clocks[0].clock.get.should eq(51_u64)
    sync_mgr.worker_clocks[1].clock.get.should eq(52_u64)
  end

  it "updates global_min when recomputing due to worker running ahead" do
    sync_mgr = SyncManager.new(2)
    sync_mgr.update_loader_time(1_u64)

    # Worker 0 advances normally
    sync_mgr.record_progress(0, 1_u64)
    sync_mgr.global_min.get.should eq(0_u64)  # Not updated yet, because worker_1 still at 0.

    # Worker 0 tries to jump way ahead (beyond LAYER_DELAY)
    sync_mgr.record_progress(0, 2_u64)

    # global_min should now be recomputed as min(worker clocks, loader_time)
    # Worker 0 is at 2, others at 0, loader at 1 → min = 0
    sync_mgr.global_min.get.should eq(0_u64)
  end

  it "includes loader_time in polled_min calculation" do
    sync_mgr = SyncManager.new(2)
    sync_mgr.update_loader_time(200_u64)

    # Both workers at 200
    sync_mgr.record_progress(0, 200_u64)
    sync_mgr.record_progress(1, 200_u64)

    # Advance loader to 300
    sync_mgr.update_loader_time(300_u64)

    # Worker 0 tries to jump to 302 (should be blocked: limit is 301)
    sync_mgr.record_progress(0, 301_u64)
    sync_mgr.update_loader_time(301_u64)

    # Worker 1 at 301 should be allowed
    sync_mgr.record_progress(1, 301_u64)
  end

  it "handles a single-worker manager" do
    manager = SyncManager.new(1)

    manager.record_progress(0, 10_u64)
    manager.global_min.get.should eq 10_u64
  end

  describe "#reset_clocks" do
    it "resets global_min, loader_time, and all worker clocks" do
      sync_mgr = SyncManager.new(3)

      # Advance everything
      sync_mgr.update_loader_time(500_u64)
      sync_mgr.record_progress(0, 500_u64)
      sync_mgr.record_progress(1, 510_u64)
      sync_mgr.record_progress(2, 520_u64)

      # Reset to new base time
      sync_mgr.reset_clocks(1000_u64)

      sync_mgr.global_min.get.should eq(1000_u64)
      sync_mgr.loader_time.get.should eq(1000_u64)
      sync_mgr.worker_clocks.each(&.clock.get.should eq(1000_u64))
    end
  end

  describe "#set_last_event_time" do
    it "sets last_event_time and resets all worker_done flags" do
      sync_mgr = SyncManager.new(3)

      # Initially all workers are not done
      3.times do |i|
        sync_mgr.worker_finished_sample?(i).should be_false
      end

      # Set sample end time
      sync_mgr.update_last_event_time(500_u64)

      # All workers should still be not done
      3.times do |i|
        sync_mgr.worker_finished_sample?(i).should be_false
      end
    end

    it "resets worker_done flags when starting a new sample" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      # Both workers report completion.
      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 100_u64)

      sync_mgr.worker_finished_sample?(0).should be_true
      sync_mgr.worker_finished_sample?(1).should be_true
      sync_mgr.all_workers_finished_sample?.should be_true

      # Only now start the next sample.
      sync_mgr.update_last_event_time(200_u64)

      sync_mgr.worker_finished_sample?(0).should be_false
      sync_mgr.worker_finished_sample?(1).should be_false
      sync_mgr.all_workers_finished_sample?.should be_false
    end
  end

  describe "#worker_finished_sample?" do
    it "returns true when worker time >= last_event_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      # Worker 0 at time 99 should not be done
      sync_mgr.record_progress(0, 99_u64)
      sync_mgr.worker_finished_sample?(0).should be_false

      # Worker 0 at time 100 should be done
      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.worker_finished_sample?(0).should be_true

      # Worker 0 at time 101 should still be done
      sync_mgr.record_progress(0, 101_u64)
      sync_mgr.worker_finished_sample?(0).should be_true
    end

    it "tracks each worker independently" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      # Only worker 1 advances past last_event_time
      sync_mgr.record_progress(0, 90_u64)
      sync_mgr.record_progress(1, 110_u64)
      sync_mgr.record_progress(2, 95_u64)

      sync_mgr.worker_finished_sample?(0).should be_false
      sync_mgr.worker_finished_sample?(1).should be_true
      sync_mgr.worker_finished_sample?(2).should be_false
    end
  end

  describe "#all_workers_finished_sample?" do
    it "returns true only when all workers are done" do
      sync_mgr = SyncManager.new(3)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      # No workers done yet
      sync_mgr.all_workers_finished_sample?.should be_false

      # One worker done
      sync_mgr.record_progress(0, 150_u64)
      sync_mgr.all_workers_finished_sample?.should be_false

      # Two workers done
      sync_mgr.record_progress(1, 150_u64)
      sync_mgr.all_workers_finished_sample?.should be_false

      # All workers done
      sync_mgr.record_progress(2, 150_u64)
      sync_mgr.all_workers_finished_sample?.should be_true
    end

    it "returns true immediately if all workers are already past last_event_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(50_u64)
      sync_mgr.update_loader_time(50_u64)

      # Both workers advance past last_event_time
      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 100_u64)

      sync_mgr.all_workers_finished_sample?.should be_true
    end
  end

  describe "#reset_clocks" do
    it "resets global_min, loader_time, worker clocks, and completion flags" do
      sync_mgr = SyncManager.new(3)

      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 110_u64)
      sync_mgr.record_progress(2, 120_u64)

      sync_mgr.all_workers_finished_sample?.should be_true

      sync_mgr.reset_clocks(1_000_u64)

      sync_mgr.global_min.get.should eq(1_000_u64)
      sync_mgr.loader_time.get.should eq(1_000_u64)
      sync_mgr.last_event_time.should eq(1_000_u64)
      sync_mgr.all_workers_finished_sample?.should be_false

      sync_mgr.worker_clocks.each do |worker_clock|
        worker_clock.clock.get.should eq(1_000_u64)
        worker_clock.done?.should be_false
      end
    end
  end

  describe "integration: sample processing workflow" do
    it "supports full sample lifecycle: set end time, process, detect completion, reset" do
      sync_mgr = SyncManager.new(3)

      # Sample 1: events from t=0 to t=100
      sample1_end = 100_u64
      sync_mgr.reset_clocks(0_u64)
      sync_mgr.update_last_event_time(sample1_end)
      sync_mgr.update_loader_time(sample1_end)

      # Workers process at different rates
      sync_mgr.record_progress(0, 80_u64)
      sync_mgr.record_progress(1, 90_u64)
      sync_mgr.record_progress(2, 95_u64)

      sync_mgr.all_workers_finished_sample?.should be_false

      # All workers finish sample 1
      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.record_progress(1, 105_u64)
      sync_mgr.record_progress(2, 110_u64)

      sync_mgr.all_workers_finished_sample?.should be_true

      # Reset for sample 2: events from t=200 to t=300
      sample2_start = 200_u64
      sample2_end = 300_u64
      sync_mgr.reset_clocks(sample2_start)
      sync_mgr.update_last_event_time(sample2_end)
      sync_mgr.update_loader_time(sample2_end)

      # All workers should be reset to not done
      sync_mgr.all_workers_finished_sample?.should be_false

      # Workers process sample 2
      sync_mgr.record_progress(0, 250_u64)
      sync_mgr.record_progress(1, 280_u64)
      sync_mgr.record_progress(2, 300_u64)

      sync_mgr.all_workers_finished_sample?.should be_false

      # Workers process sample 2
      sync_mgr.record_progress(0, 300_u64)
      sync_mgr.record_progress(1, 300_u64)
      sync_mgr.record_progress(2, 300_u64)

      sync_mgr.all_workers_finished_sample?.should be_true
    end
  end

  describe "edge cases" do
    it "handles worker at exactly last_event_time" do
      sync_mgr = SyncManager.new(1)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      sync_mgr.record_progress(0, 100_u64)
      sync_mgr.worker_finished_sample?(0).should be_true
    end

    it "handles last_event_time of 0" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(0_u64)
      sync_mgr.update_loader_time(0_u64)

      # Workers at time 0 should be done
      sync_mgr.record_progress(0, 0_u64)
      sync_mgr.record_progress(1, 0_u64)

      sync_mgr.all_workers_finished_sample?.should be_true
    end

    it "handles workers advancing far beyond last_event_time" do
      sync_mgr = SyncManager.new(2)
      sync_mgr.update_last_event_time(100_u64)
      sync_mgr.update_loader_time(100_u64)

      # Workers jump way past last_event_time
      sync_mgr.record_progress(0, 1000_u64)
      sync_mgr.record_progress(1, 2000_u64)

      sync_mgr.all_workers_finished_sample?.should be_true
    end
  end
end
