class WorkerClock
  getter clock = Atomic(UInt64).new(0_u64)
end

class SyncManager
  LOOKAHEAD = 1_u64

  getter global_min = Atomic(UInt64).new(0_u64)
  @worker_clocks : Array(WorkerClock)

  def initialize(worker_count : Int32)
    @worker_clocks = Array(WorkerClock).new(worker_count) { WorkerClock.new }
  end

  # Returns true if the worker is allowed to proceed, false if it should wait.
  def update_and_sync(worker_id : Int32, worker_time : UInt64) : Bool
    cached_min = @global_min.get
    if worker_time > cached_min + LOOKAHEAD
      # Recompute true minimum across workers.
      polled_min = @worker_clocks.min_of(&.clock.get)
      @global_min.set(polled_min)

      if worker_time > polled_min + LOOKAHEAD
        return false
      end
    end

    # Publish this worker's current time.
    # Only times from workers that are within the allowed window contribute to future true_min calculations.
    @worker_clocks[worker_id].clock.set(worker_time)
    true
  end
end
