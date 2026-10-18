require "./network"
require "./nmnist_loader.cr"
require "./constant"
require "./type"
require "option_parser"

Fiber::ExecutionContext.default.resize(maximum: MAX_WORKERS.to_i + LOADER_COUNT)
# Default values for runtime:
network_type = NETWORK_TYPE
layer_sizes = LAYER_SIZES
train_samples_count = TRAIN_COUNT
test_samples_count = TEST_COUNT
label_filter = nil

OptionParser.parse do |parser|
  parser.banner = "Usage: crystal run main.cr [arguments]"
  parser.on("-n NETWORK_TYPE", "--network_type=NETWORK_TYPE", "Specify the network type (default: lif)") do |n|
    network_type = n
  end
  parser.on("-l LAYER_SIZES", "--layer_sizes=LAYER_SIZES", "Number of nodes in network, by layer(default: #{LAYER_SIZES}). Note that if NMNIST data is fed, the input layer must have 2312 nodes.") do |l|
    if parsed_count = l.split(',').map(&.strip.to_u32)
      layer_sizes = parsed_count
    else
      STDERR.puts "Error: '--layer_sizes' expects an comma-separated list of integers, got '#{l}'"
      STDERR.puts parser
      exit(1)
    end
  end
  parser.on("-t TRAIN_COUNT", "--train_samples_count=TRAIN_COUNT", "Number of training samples (default: 1)") do |t|
    if parsed_count = t.to_u32?
      train_samples_count = parsed_count
    else
      STDERR.puts "Error: '--train_samples_count' expects an integer, got '#{t}'"
      STDERR.puts parser
      exit(1)
    end
  end
  parser.on("-e TEST_COUNT", "--test_samples_count=TEST_COUNT", "Number of test samples (default: 1)") do |e|
    if parsed_count = e.to_u32?
      test_samples_count = parsed_count
    else
      STDERR.puts "Error: '--test_samples_count' expects an integer, got '#{e}'"
      STDERR.puts parser
      exit(1)
    end
  end
  parser.on("-f LABEL_FILTER", "--label_filter=LABEL_FILTER", "Specify the label filter (default: none)") do |f|
    label_filter = f
  end
end

def train_and_test(network_type, layer_sizes, train_samples_count, test_samples_count, label_filter)
  sample_channel = Channel(NMnistSample).new(capacity: SAMPLE_CAPACITY)
  target_path = TRAIN_DATA + (label_filter ? "/#{label_filter}" : "")
  spawn(name: "nmnist_loader") do
    NMnistLoader.stream_samples(target_path, train_samples_count, sample_channel)
  end

  network = case network_type
  when "lif"
    Network(LIFNode, Tuple(UInt8, Float64), Tuple(UInt8, Bool)).new(layer_sizes, worker_count: MAX_WORKERS, layer_latency: LAYER_LATENCY, max_drift: MAX_DRIFT, training: true)
  when "accumulator"
    Network(AccumulatorNode, UInt64, UInt64).new(layer_sizes, worker_count: MAX_WORKERS, layer_latency: LAYER_LATENCY, max_drift: MAX_DRIFT, training: true)
  else
    raise "Unknown network type: #{network_type}. Use 'lif' or 'accumulator'."
  end
  sample_counter = 0
  while sample = sample_channel.receive?
    sample_counter += 1
    network.reset(NMnistLoader.sample_start_time(sample), NMnistLoader.sample_end_time(sample))
    sample.events.each do |event|
      network.input(NMnistLoader.flatten(event), event.t, {sample.label, 1.0})
    end
    network.run
    puts "Trained sample #{sample_counter}/#{train_samples_count}" if sample_counter % 100 == 0
  end
end

train_and_test(network_type, layer_sizes, train_samples_count, test_samples_count, label_filter)
