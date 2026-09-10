require "spec"
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
  it "initializes the global minimum to zero" do
    manager = SyncManager.new(2)

    manager.global_min.get.should eq 0_u64
  end

  it "allows a worker at the current minimum to proceed" do
    manager = SyncManager.new(2)

    manager.update_and_sync(0, 0_u64).should be_true
    manager.global_min.get.should eq 0_u64
  end

  it "allows a worker one tick ahead of the minimum to proceed" do
    manager = SyncManager.new(2)

    manager.update_and_sync(0, 1_u64).should be_true
  end

  it "blocks a worker more than one tick ahead of the true minimum" do
    manager = SyncManager.new(2)

    manager.update_and_sync(1, 0_u64).should be_true
    manager.update_and_sync(0, 2_u64).should be_false
    manager.global_min.get.should eq 0_u64
  end

  it "publishes the local time when the worker is allowed to proceed" do
    manager = SyncManager.new(2)
    manager.update_and_sync(0, 0_u64).should be_true
    manager.update_and_sync(1, 0_u64).should be_true
    manager.update_and_sync(0, 1_u64).should be_true
    manager.update_and_sync(1, 1_u64).should be_true
  end

  it "does not update the global minimum until a worker exceeds the lookahead" do
    manager = SyncManager.new(2)
    manager.global_min.get.should eq 0_u64
    manager.update_and_sync(0, 1_u64).should be_true
    manager.update_and_sync(1, 1_u64).should be_true
    manager.global_min.get.should eq 0_u64
    # Now push one worker far enough to trigger recomputation
    manager.update_and_sync(0, 3_u64).should be_false
    manager.global_min.get.should eq 1_u64
  end

  it "handles a single-worker manager" do
    manager = SyncManager.new(1)

    manager.update_and_sync(0, 10_u64).should be_false
    manager.global_min.get.should eq 0_u64
  end
end
