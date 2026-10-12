require "./network"
require "./nmnist_loader.cr"
require "./constant"
require "./type"

LOADER_COUNT = 1
Fiber::ExecutionContext.default.resize(maximum: MAX_WORKERS.to_i + LOADER_COUNT)

def train_and_test(network_type, layer_sizes, train_samples_count, test_samples_count, sample)
  sample_channel = Channel(NMnistSample).new(capacity: SAMPLE_CAPACITY)
  target_path = TRAIN_DATA + (sample ? "/#{sample}" : "")
  spawn(name: "nmnist_loader") do
    NMnistLoader.stream_samples(target_path, train_samples_count, sample_channel)
  end

  network = case network_type
  when "lif"
    Network(LIFNode, Float64, Bool).new(layer_sizes, worker_count: MAX_WORKERS, layer_latency: LAYER_LATENCY, max_drift: MAX_DRIFT, training: true)
  when "accumulator"
    Network(AccumulatorNode(UInt64), UInt64, UInt64).new(layer_sizes, worker_count: MAX_WORKERS, layer_latency: LAYER_LATENCY, max_drift: MAX_DRIFT, training: true)
  else
    raise "Unknown network type: #{network_type}. Use 'lif' or 'accumulator'."
  end
  sample_counter = 0
  while sample = sample_channel.receive?
    sample_counter += 1
    network.reset(NMnistLoader.sample_start_time(sample), NMnistLoader.sample_end_time(sample))
    sample.events.each do |event|
      network.input(NMnistLoader.flatten(event), event.t)
    end
    network.run
    puts "Trained sample #{sample_counter}/#{train_samples_count}" if sample_counter % 100 == 0
  end
end

network_type = ARGV[0]? || "lif"
layer_sizes = [ARGV[1]?.try(&.to_u32) || 1_u32]
train_samples_count = ARGV[2]?.try(&.to_u32) || 1_u32
test_samples_count = ARGV[3]?.try(&.to_u32) || 1_u32
sample = ARGV[4]?.try(&.to_u32)

train_and_test(network_type, layer_sizes, train_samples_count, test_samples_count, sample)
