require "./constants"

class WorkerClock
  getter next_tick = Atomic(UInt64).new(0_u64)
  @done = Atomic(Bool).new(false)

  def mark_done : Void
    @done.set(true)
  end

  def done? : Bool
    @done.get
  end

  def reset(time : UInt64) : Void
    next_tick.set(time)
    @done.set(false)
  end
end

class SyncManager
  getter worker_clocks
  @end_time = Atomic(UInt64).new(0_u64)
  @active = Atomic(Bool).new(false)

  def activate : Void
    @active.set(true)
  end

  def deactivate : Void
    @active.set(false)
  end

  def active? : Bool
    @active.get
  end

  def initialize(worker_count : Int32)
    @worker_clocks = Array(WorkerClock).new(worker_count) { WorkerClock.new }
  end

  def worker_finished_sample?(worker_id : Int32) : Bool
    @worker_clocks[worker_id].done?
  end

  def all_workers_finished_sample? : Bool
    @worker_clocks.all?(&.done?)
  end

  def end_time : UInt64
    @end_time.get
  end

  # Workers cannot advance past peer workers + MAX_DRIFT.
  def safe_time(worker_id : Int32) : UInt64
    return 0_u64 unless @active.get
    return @end_time.get if @worker_clocks.size <= 1
    min_peer_next_tick = UInt64::MAX
    @worker_clocks.each_with_index do |worker_clock, idx|
      next if idx == worker_id
      next_tick = worker_clock.next_tick.get
      min_peer_next_tick = next_tick if next_tick < min_peer_next_tick
    end
    safe_time = min_peer_next_tick + MAX_DRIFT
    end_time = @end_time.get
    safe_time > end_time ? end_time : safe_time
  end

  def record_progress(worker_id : Int32, worker_time : UInt64) : Void
    worker_clock = @worker_clocks[worker_id]
    worker_clock.next_tick.set(worker_time)
    worker_clock.mark_done if worker_time >= @end_time.get
  end

  def reset(end_time : UInt64) : Void
    @worker_clocks.each(&.next_tick.set(0))
    @end_time.set(end_time)
  end
end
