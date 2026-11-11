require "./constant"
WORKER_CONTEXT = Fiber::ExecutionContext::Parallel.new("workers", maximum: WORKERS)
LOADER_CONTEXT = Fiber::ExecutionContext::Parallel.new("loaders", maximum: LOADERS)

class Worker
  getter id
  getter event_slice_channel

  def initialize(@id : UInt8, @network : Network)
    @event_slice_channel = Channel(UInt16).new(1)
    @history = StaticArray(Slice(UInt32), LADDER_SIZE).new(Slice(UInt32).empty)
    @history_count = 0_u8
  end

  def run
    WORKER_CONTEXT.spawn do
      while event_slice_idx = @event_slice_channel.receive?
        success = true
        (LADDER_SIZE - 1).downto(1) do |i|
          @history[i] = @history[i - 1]
        end
        @history[0] = @network.event_slice(event_slice_idx)
        @history_count = [@history_count + 1, LADDER_SIZE].min
        @history_count.times do |i|
          slice = @history[i]
          slice.each do |number|
            # puts "Worker #{@id} processed event #{number}"
            break if number == UInt32::MAX
          end
        end
        @network.result_chan.send({@id, :success}) if success
      end
    end
  end
end

class Network
  getter result_chan
  @workers : Array(Worker)
  @events : Slice(UInt32)

  def initialize
    @result_chan = Channel(Tuple(UInt8, Symbol)).new
    @workers = [] of Worker
    @events = Slice(UInt32).new(TOTAL_SIZE, 0_u16)
    50.times do |window_index|
      base = window_index << WINDOW_BITS
      100.times do |slot_index|
        @events[base + slot_index] = slot_index.to_u16
      end
      @events[base + 100] = UInt32::MAX
    end

    # Initialisation of nulls complete, can now refer to self.
    @workers = Array.new(WORKERS) { |id| Worker.new(id.to_u8, self) }
  end

  def event_slice(event_slice_idx : UInt16)
     offset = event_slice_idx << WINDOW_BITS
     @events[offset, WINDOW_SIZE]
   end

  def run
    @workers.each do |worker|
      worker.run
    end

    50_u16.times do |window|
      @workers.each do |worker|
        worker.event_slice_channel.send(window)
      end
      fail_count = 0
      @workers.size.times do
        worker_id, result = @result_chan.receive
        case result
        when :fail
          puts "-> Worker #{worker_id} failed window #{window}."
          fail_count += 1
        when :success
          puts "-> Worker #{worker_id} finished window #{window}."
        end
      end
      if fail_count > 0
        puts "-------- #{fail_count} failures detected  ----------"
      end
      current_slice = event_slice(window)
      current_slice.each_with_index do |val, idx|
        break if val == UInt32::MAX
        current_slice[idx] = val + LAYER_LATENCY
      end
    end
    @workers.each do |worker|
      worker.event_slice_channel.close
    end
    puts "Network run completed."
  end
end

network = Network.new
network.run
