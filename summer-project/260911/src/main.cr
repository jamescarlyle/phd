require "./wheel"
require "./sync_manager"
require "./cross_worker_comm"
require "./node"
require "./worker"
require "./router"

LAYER_SIZES = [2312, 200, 200, 10]
WORKER_COUNT = ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
Fiber::ExecutionContext.default.resize(WORKER_COUNT)

puts "Configuring Synchronized Network Architecture:"
puts " - Layer Sizes: #{LAYER_SIZES.inspect}"
puts " - Execution Threads: #{WORKER_COUNT}"

sync_mgr = SyncManager.new(WORKER_COUNT)

# Calculate contiguous ID boundaries per layer.
layer_bounds = Array(LayerBounds).new
total_nodes_count = 0_u32

LAYER_SIZES.each do |size|
  start_id = total_nodes_count
  end_id = total_nodes_count + size.to_u32 - 1_u32
  layer_bounds << LayerBounds.new(start_id, end_id)
  total_nodes_count += size.to_u32
end

all_nodes = Array(Node).new
node_id = 0_u32
LAYER_SIZES.each_with_index do |size, layer_idx|
  size.times do
    all_nodes << Node.new(node_id, layer_idx)
    node_id += 1_u32
  end
end

workers = Array(Worker).new(WORKER_COUNT) do |i|
  Worker.new(i, current_time: 0, worker_count: WORKER_COUNT)
end
router = Router.new(workers, layer_bounds, WORKER_COUNT)

workers.each do |worker|
  spawn do
    worker_id = worker.id
    loop do
      local_time = worker.wheel.current_time

      unless sync_mgr.update_and_sync(worker_id, local_time)
        Fiber.yield
        next
      end

      worker.drain_all_incoming

      worker.wheel.tick do |event|
        node = all_nodes[event.target_node]
        new_state = node.process(event.payload)
        router.dispatch(node, new_state, worker_id)
      end
    end
  end
end

train_data = NMnistLoader.load_data(TRAIN_DATA + (digit ? "/" + digit : ""), train_samples_count)
puts "Starting training."
train_data.each_with_index do |sample, idx|
  # Reset network.
  network.reset_network(sample.events[0].t)
  # Present sequence of events.
  sample.events.each do |ev|
    input_neuron_idx = (ev.p * 34 * 34) + ev.y * 34 + ev.x
    network.input(input_neuron_idx, ev.t)
  end
  pred = network.predict(sample.events.last.t)
  network.apply_eligibility_to_weights(pred, sample.label) if pred
  puts "Trained sample #{idx+1}/#{train_samples_count}" if (idx + 1) % 100 == 0
end


puts "Seeding initial spikes into Layer 0."
layer0 = layer_bounds[0]
l0_size = layer0.end_id - layer0.start_id + 1

256.times do |i|
  target_id = layer0.start_id + (i % l0_size)
  target_worker_id = (target_id % WORKER_COUNT).to_i
  workers[target_worker_id].enqueue_from(target_worker_id, target_id, 1_u64, 1.0)
end

spawn do
  seq = 0_u64
  loop do
    sleep 2.milliseconds
    seq += 1
    32.times do |j|
      target_id = layer0.start_id + ((j * 7 + seq.to_i) % l0_size)
      target_worker_id = (target_id % WORKER_COUNT).to_i
      workers[target_worker_id].enqueue_from(target_worker_id, target_id, 100_u64, 1.0)
    end
  end
end

puts "Running execution loop."
start_time = Time.instant
last_total = 0_u64

15.times do
  sleep 1.second
  elapsed = (Time.instant - start_time).total_seconds
  total_processed = all_nodes.sum(&.processed_count)
  delta = total_processed - last_total
  last_total = total_processed
  puts "T=%4.1fs | Total Processed: %10d | Rate: %8d msgs/s" % [
    elapsed, total_processed, delta
  ]
end
