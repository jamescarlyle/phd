require "./wheel"
require "./sync_manager"
require "./cross_worker_comm"
require "./node"
require "./worker"
require "./router"
require "./nmnist_loader.cr"
require "./constants"
require "./network"

WORKER_COUNT = ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
Fiber::ExecutionContext.default.resize(WORKER_COUNT)

puts "Configuring Synchronized Network Architecture:"
puts " - Layer Sizes: #{LAYER_SIZES.inspect}"
puts " - Execution Threads: #{WORKER_COUNT}"

def train_and_test(train_samples_count, test_samples_count, digit)
  network = Network.new(LAYER_SIZES, WORKER_COUNT, false)
  network.run

  train_data = NMnistLoader.load_data(TRAIN_DATA + (digit ? "/" + digit : ""), train_samples_count)
  train_data.each_with_index do |sample, idx|
    # Reset network.
    network.reset_network(sample.events[0].t)
    # Present sequence of events.
    sample.events.each do |ev|
      input_neuron_idx = (ev.p * 34 * 34) + ev.y * 34 + ev.x
      network.input(input_neuron_idx, ev.t)
    end
    # pred = network.predict(sample.events.last.t)
    # network.apply_eligibility_to_weights(pred, sample.label) if pred
    puts "Trained sample #{idx+1}/#{train_samples_count}" if (idx + 1) % 100 == 0
  end
end

# puts "Seeding initial spikes into Layer 0."
# layer0 = layer_bounds[0]
# l0_size = layer0.end_id - layer0.start_id + 1

# 256.times do |i|
#   target_id = layer0.start_id + (i % l0_size)
#   target_worker_id = (target_id % WORKER_COUNT).to_i
#   workers[target_worker_id].enqueue(target_worker_id, target_id, 1_u64, 1.0)
# end

# spawn do
#   seq = 0_u64
#   loop do
#     sleep 2.milliseconds
#     seq += 1
#     32.times do |j|
#       target_id = layer0.start_id + ((j * 7 + seq.to_i) % l0_size)
#       target_worker_id = (target_id % WORKER_COUNT).to_i
#       workers[target_worker_id].enqueue(target_worker_id, target_id, 100_u64, 1.0)
#     end
#   end
# end

# puts "Running execution loop."
# start_time = Time.instant
# last_total = 0_u64

# 15.times do
#   sleep 1.second
#   elapsed = (Time.instant - start_time).total_seconds
#   total_processed = all_nodes.sum(&.processed_count)
#   delta = total_processed - last_total
#   last_total = total_processed
#   puts "T=%4.1fs | Total Processed: %10d | Rate: %8d msgs/s" % [
#     elapsed, total_processed, delta
#   ]
# end

train_and_test(ARGV[0].to_i32, ARGV[1].to_i32, ARGV[2]?)
