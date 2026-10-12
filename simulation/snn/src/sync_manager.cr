# Cache line size on Apple Silicon ARM64 is 64 bytes.
# Pad each worker's state so every worker sits in its own cache line.
struct WorkerState
  @active : Atomic(Bool)
  @next_tick : Atomic(UInt64)

  # Intended for a 64-byte slot on the target platform.
  # Verify with sizeof; this does not enforce cache-line alignment.
  @_pad = StaticArray(UInt8, 48).new(0_u8)

  def initialize(active = false, next_tick = 0_u64)
    @active = Atomic(Bool).new(active)
    @next_tick = Atomic(UInt64).new(next_tick)
  end

  @[AlwaysInline]
  def active=(active : Bool) : Nil
    @active.set(active, :release)
    nil
  end

  @[AlwaysInline]
  def active? : Bool
    @active.get(:acquire)
  end

  @[AlwaysInline]
  def next_tick=(tick : UInt64) : Nil
    @next_tick.set(tick, :release)
    nil
  end

  @[AlwaysInline]
  def next_tick : UInt64
    @next_tick.get(:acquire)
  end
end

class SyncManager
  getter worker_count
  getter layer_latency
  getter max_drift
  @start_time = Atomic(UInt64).new(0_u64)
  @last_process_time = Atomic(UInt64).new(0_u64)

  def initialize(@worker_count : UInt32, @layer_latency : UInt64 = LAYER_LATENCY, @max_drift : UInt64 = MAX_DRIFT)
    @worker_states = Array(WorkerState).new(worker_count) { WorkerState.new }
  end

  @[AlwaysInline]
  private def worker_ptr(worker_id : UInt32) : Pointer(WorkerState)
    unless 0 <= worker_id && worker_id < @worker_states.size
      raise IndexError.new("Invalid worker ID: #{worker_id}")
    end
    @worker_states.to_unsafe + worker_id
  end

  @[AlwaysInline]
  def worker_active?(worker_id : UInt32) : Bool
    worker_ptr(worker_id).value.active?
  end

  @[AlwaysInline]
  def set_worker_active(worker_id : UInt32, active : Bool) : Nil
    worker_ptr(worker_id).value.active=(active)
  end

  @[AlwaysInline]
  def worker_next_tick(worker_id : UInt32) : UInt64
    worker_ptr(worker_id).value.next_tick
  end

  @[AlwaysInline]
  def set_worker_next_tick(worker_id : UInt32, new_step : UInt64)
    worker_ptr(worker_id).value.next_tick=(new_step)
  end

  def all_workers_at_time?(time : UInt64) : Bool
    @worker_states.each_with_index(0_u32) do |_, worker_id|
      next unless worker_active?(worker_id)
      return false if worker_next_tick(worker_id) < time
    end
    true
  end

  @[AlwaysInline]
  private def saturating_add(a : UInt64, b : UInt64) : UInt64
    sum = a &+ b
    sum < a ? UInt64::MAX : sum
  end

  # Workers cannot advance past peer workers + @max_drift.
  def horizon_next_tick(worker_id : UInt32) : UInt64
    last_process_time = @last_process_time.get
    this_worker_next_tick = worker_next_tick(worker_id)
    optimal_next_tick = saturating_add(this_worker_next_tick, @layer_latency)
    optimal_next_tick = last_process_time if last_process_time < optimal_next_tick
    worker_count = @worker_count
    if worker_count > 1
      min_peer_next_tick = UInt64::MAX
      peer_id = 0_u32
      while peer_id < worker_count
        if peer_id != worker_id
          peer_next_tick = worker_next_tick(peer_id)
          if peer_next_tick < min_peer_next_tick
            min_peer_next_tick = peer_next_tick
          end
        end
        peer_id += 1_u32
      end
      peer_plus_drift = saturating_add(min_peer_next_tick, @max_drift)
      optimal_next_tick = peer_plus_drift if peer_plus_drift < optimal_next_tick
    end
    optimal_next_tick
  end

  def record_progress(worker_id : UInt32, worker_next_tick : UInt64) : Void
    set_worker_next_tick(worker_id, worker_next_tick)
    set_worker_active(worker_id, false) if worker_next_tick >= @last_process_time.get
  end

  def reset(start_time : UInt64, last_process_time : UInt64) : Void
    @worker_states.each_with_index(0_u32) do |_, worker_id|
      set_worker_active(worker_id, true)
      set_worker_next_tick(worker_id, start_time)
    end
    @start_time.set(start_time)
    @last_process_time.set(last_process_time)
  end
end
