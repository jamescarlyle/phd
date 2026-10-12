require "./hierarchical_clock"
require "./sync_manager"
require "./cross_worker_comm"
require "./node"
require "./worker"
require "./router"
require "./nmnist_loader.cr"
require "./constants"
require "./network"

WORKER_COUNT = ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
# Crystal 1.21+ scales the default execution context across CPU cores:
Fiber::ExecutionContext.default.resize(maximum: WORKER_COUNT + 1)

puts "Configuring Synchronized Network Architecture:"
puts " - Layer Sizes: #{LAYER_SIZES.inspect}"
puts " - Execution Threads: #{WORKER_COUNT}"

def train_and_test(train_samples_count, test_samples_count, digit)
  network = Network.new(LAYER_SIZES, WORKER_COUNT, false)
  network.run

  # Bounded channel allows prefetching up to 4 parsed samples in memory.
  sample_channel = Channel(NMnistSample).new(capacity: 4)
  target_path = TRAIN_DATA + (digit ? "/#{digit}" : "")

  # Spawn the disk/parser loader fiber.
  spawn(name: "nmnist_loader") do
    NMnistLoader.stream_samples(target_path, train_samples_count, sample_channel)
  end

  idx = 0
  # Pull samples from the channel until the loader closes it.
  while sample = sample_channel.receive?
    idx += 1
    end_time = sample.events[-1].t + (LAYER_SIZES.size.to_u64 * LAYER_DELAY) + 1
    # Reset network clocks and state for this sample
    network.reset(end_time)

    # Feed all external events for this sample up-front
    sample.events.each do |event|
      input_neuron_idx = (event.p * 34 * 34) + event.y * 34 + event.x
      network.input(input_neuron_idx.to_u32, event.t)
    end
    # network.workers.each(&.drain_all_incoming)

    network.sync_mgr.activate
    # Wait for worker fibers to simulate the sample to completion
    until network.sync_mgr.all_workers_finished_sample?
      Fiber.yield
    end
    network.sync_mgr.deactivate
    puts "Trained sample #{idx}/#{train_samples_count}" if idx % 100 == 0
  end
end

train_and_test(ARGV[0].to_i32, ARGV[1].to_i32, ARGV[2]?)
