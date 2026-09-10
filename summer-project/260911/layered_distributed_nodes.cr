# layered_distributed_nodes.cr
# Zero-allocation, layered, fully connected feed-forward network simulation
# for thousands of virtual processors on macOS Apple Silicon (M4).
# Uses Time::Instant (no deprecated Time.monotonic).

# -----------------------------------------------------------------------------
# 1. Message definition (value type, no heap allocation)
# -----------------------------------------------------------------------------
struct Message
  getter sender_layer : UInt16
  getter sender_id    : UInt32
  getter sequence     : UInt64
  getter payload      : Float64
  getter deliver_at   : Time::Instant

  def initialize(@sender_layer : UInt16, @sender_id : UInt32,
                 @sequence : UInt64, @payload : Float64, @deliver_at : Time::Instant)
  end

  def self.empty : self
    new(0_u16, 0_u32, 0_u64, 0.0, Time.instant)
  end
end

# -----------------------------------------------------------------------------
# 2. Lossy fixed-capacity mailbox (drop-oldest ring buffer)
# -----------------------------------------------------------------------------
class LossyMailbox(T, N)
  @buffer : StaticArray(T, N)
  @head   : Int32 = 0
  @tail   : Int32 = 0
  @count  : Int32 = 0
  @dropped : UInt64 = 0_u64

  def initialize(default_val : T)
    @buffer = StaticArray(T, N).new(default_val)
  end

  # Push message; if full, overwrite oldest (tail) to keep real-time behavior.
  def push(item : T) : Bool
    dropped = false
    if @count == N
      @tail = (@tail + 1) % N
      @dropped &+= 1
      dropped = true
    else
      @count += 1
    end
    @buffer[@head] = item
    @head = (@head + 1) % N
    dropped
  end

  def peek : T?
    return nil if @count == 0
    @buffer[@tail]
  end

  def pop : T?
    return nil if @count == 0
    item = @buffer[@tail]
    @tail = (@tail + 1) % N
    @count -= 1
    item
  end

  def size : Int32
    @count
  end

  def dropped_count : UInt64
    @dropped
  end
end

# -----------------------------------------------------------------------------
# 3. Layered network fabric with fixed delays and pre-allocated structures
# -----------------------------------------------------------------------------
class LayeredNetworkFabric
  TRANSIT_DELAY = 1.milliseconds

  getter layer_sizes : Array(Int32)
  getter layers      : Array(Array(Node)) # layers[layer_idx][node_idx]
  @total_nodes       : Int32

  def initialize(layer_sizes : Array(Int32))
    @layer_sizes = layer_sizes
    @total_nodes = layer_sizes.sum
    @layers = Array(Array(Node)).new(layer_sizes.size)
    layer_sizes.each { |size| @layers << Array(Node).new(size) }
  end

  def register_node(node : Node, layer_idx : Int32) : Void
    @layers[layer_idx] << node
  end

  # Fully connected feed-forward: each node in layer L sends to all nodes in L+1
  # with a fixed transit delay and optional fan-out probability.
  def dispatch_forward(from_node : Node, from_layer_idx : Int32,
                       seq : UInt64, val : Float64,
                       fanout_prob : Float64 = 1.0) : Void
    next_layer = from_layer_idx + 1
    return unless next_layer < @layers.size

    target_nodes = @layers[next_layer]
    return if target_nodes.empty?

    # Deterministic pseudo-random selection using node id and sequence
    seed = from_node.id.hash ^ seq.hash
    target_nodes.each_with_index do |target, idx|
      if fanout_prob < 1.0
        prob_val = ((seed &+ idx.to_u64) & 0xFFFF).to_f32 / 65536.0
        next if prob_val >= fanout_prob
      end

      arrival_time = Time.instant + TRANSIT_DELAY
      msg = Message.new(
        from_layer_idx.to_u16,
        from_node.id,
        seq,
        val,
        arrival_time
      )
      target.receive_message(msg)
    end
  end

  def all_nodes : Array(Node)
    result = Array(Node).new(@total_nodes)
    @layers.each do |layer|
      layer.each { |n| result << n }
    end
    result
  end
end

# -----------------------------------------------------------------------------
# 4. Processing node with layer awareness
# -----------------------------------------------------------------------------
class Node
  # Tune this to balance memory vs drop rate.
  MAILBOX_CAPACITY = 1024

  getter id           : UInt32
  getter layer_index  : Int32
  getter processed_count : UInt64 = 0_u64
  @mailbox            : LossyMailbox(Message, MAILBOX_CAPACITY)
  @network            : LayeredNetworkFabric
  @local_seq          : UInt64 = 0_u64
  @state_accumulator  : Float64 = 0.0

  def initialize(@id : UInt32, @layer_index : Int32,
                 @network : LayeredNetworkFabric)
    @mailbox = LossyMailbox(Message, MAILBOX_CAPACITY).new(Message.empty)
  end

  def receive_message(msg : Message) : Void
    @mailbox.push(msg)
  end

  def run : Void
    loop do
      now = Time.instant

      # Process eligible messages that have completed transit delay
      while (msg = @mailbox.peek)
        if now >= msg.deliver_at
          @mailbox.pop
          process(msg)
        else
          break
        end
      end

      # Workload: emit forward every iteration if not in last layer
      if @layer_index < @network.layer_sizes.size - 1
        @local_seq &+= 1_u64
        @network.dispatch_forward(
          self, @layer_index, @local_seq, @state_accumulator,
          fanout_prob = 1.0 # fully connected; reduce if you want sparser fan-out
        )
      end

      Fiber.yield
    end
  end

  @[AlwaysInline]
  private def process(msg : Message) : Void
    @processed_count &+= 1_u64
    @state_accumulator = (@state_accumulator * 0.95) + (msg.payload * 0.05)
  end

  def dropped_count : UInt64
    @mailbox.dropped_count
  end

  def queue_size : Int32
    @mailbox.size
  end
end

# -----------------------------------------------------------------------------
# 5. Pre-allocated distribution statistics (zero allocation in steady state)
# -----------------------------------------------------------------------------
class DistributionStats
  getter min            : UInt64 = 0_u64
  getter max            : UInt64 = 0_u64
  getter mean           : Float64 = 0.0
  getter stddev         : Float64 = 0.0
  getter p50            : UInt64 = 0_u64
  getter p90            : UInt64 = 0_u64
  getter p99            : UInt64 = 0_u64
  getter imbalance_ratio : Float64 = 0.0

  @sample_buffer : Array(UInt64)

  def initialize(capacity : Int32)
    @sample_buffer = Array(UInt64).new(capacity, 0_u64)
  end

  # Compute stats for a slice of nodes (e.g., one layer)
  def update(nodes : Array(Node)) : Void
    count = nodes.size
    return if count == 0

    sum = 0_u64
    min_val = UInt64::MAX
    max_val = 0_u64

    nodes.each_with_index do |node, idx|
      val = node.processed_count
      @sample_buffer[idx] = val
      sum &+= val
      min_val = val if val < min_val
      max_val = val if val > max_val
    end

    @min = min_val
    @max = max_val
    @mean = sum.to_f / count

    # Variance and stddev
    variance_sum = 0.0
    @sample_buffer.each do |val|
      diff = val.to_f - @mean
      variance_sum += diff * diff
    end
    @stddev = Math.sqrt(variance_sum / count)

    # Percentiles via in-place sort
    @sample_buffer.sort!

    @p50 = @sample_buffer[(count * 0.50).to_i]
    @p90 = @sample_buffer[(count * 0.90).to_i]
    @p99 = @sample_buffer[(count * 0.99).to_i]
    @imbalance_ratio = @mean > 0.0 ? (@max.to_f / @mean) : 1.0
  end
end

# -----------------------------------------------------------------------------
# 6. Bootstrapper: layered network construction and layer-aware spawning
# -----------------------------------------------------------------------------

# Define your feed-forward layered architecture here.
# Example: 4 layers with [256, 512, 512, 256] nodes each.
LAYER_SIZES = [2312, 200, 200, 10]

puts "Initializing layered network fabric: #{LAYER_SIZES.inspect}"
network = LayeredNetworkFabric.new(LAYER_SIZES)

# Pre-allocate all nodes and register them per layer
node_id = 0_u32
LAYER_SIZES.each_with_index do |size, layer_idx|
  size.times do
    node = Node.new(node_id, layer_idx, network)
    network.register_node(node, layer_idx)
    node_id &+= 1_u32
  end
end

puts "Total nodes: #{network.all_nodes.size}"

# Seed initial traffic into layer 0, then keep injecting periodically.
puts "Seeding initial spikes into layer 0..."
layer0 = network.layers[0]

# Initial burst
256.times do |i|
  target = layer0[i % layer0.size]
  msg = Message.new(
    0_u16, 0_u32, 1_u64, 1.0,
    Time.instant + LayeredNetworkFabric::TRANSIT_DELAY
  )
  target.receive_message(msg)
end

# Continuous injection fiber (one fiber, low QoS work)
spawn do
  seq = 0_u64
  loop do
    sleep 0.002.seconds # 2 ms between injection bursts
    seq &+= 1_u64
    # Inject a small batch into random layer-0 nodes
    32.times do |j|
      target = layer0[(j * 7 + seq.to_i) % layer0.size]
      msg = Message.new(
        0_u16, 0_u32, seq, 1.0,
        Time.instant + LayeredNetworkFabric::TRANSIT_DELAY
      )
      target.receive_message(msg)
    end
  end
end

# Layer-aware fiber spawning:
# Create fibers layer-by-layer to encourage uniform distribution across workers.
puts "Spawning fibers layer-by-layer..."
network.layers.each_with_index do |layer, layer_idx|
  layer.each do |node|
    spawn do
      Fiber.yield
      node.run
    end
  end
end

# -----------------------------------------------------------------------------
# 7. Resize default execution context to match P-core count
# -----------------------------------------------------------------------------

# On M4 MacBook Air: 4 P-cores + 6 E-cores.
# Use CRYSTAL_WORKERS env var to control parallelism; default to 4 (P-cores only).
maximum = ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
Fiber::ExecutionContext.default.resize(maximum)

# -----------------------------------------------------------------------------
# 8. Telemetry: per-layer distribution statistics with minimal GC pressure
# -----------------------------------------------------------------------------

stats_global = DistributionStats.new(network.all_nodes.size)
stats_per_layer = network.layers.map { |layer| DistributionStats.new(layer.size) }

puts "System running across #{System.cpu_count} CPU cores (execution context size: #{maximum}). Monitoring per-layer distribution..."
puts "-" * 110

start_time = Time.instant
last_total = 0_u64

15.times do
  sleep 1.second
  elapsed = (Time.instant - start_time).total_seconds

  all_nodes = network.all_nodes
  stats_global.update(all_nodes)

  total_processed = all_nodes.sum(&.processed_count)
  total_dropped = all_nodes.sum(&.dropped_count)
  delta = total_processed - last_total
  last_total = total_processed

  puts "T=%4.1fs | Total: %9d | Rate: %8d/s | Dropped: %7d" % [
    elapsed, total_processed, delta, total_dropped
  ]
  puts "       | Global => Min: %6d | P50: %6d | P90: %6d | P99: %6d | Max: %6d | μ: %7.1f | σ: %6.1f | Imb: %4.2fx" % [
    stats_global.min, stats_global.p50, stats_global.p90,
    stats_global.p99, stats_global.max,
    stats_global.mean, stats_global.stddev, stats_global.imbalance_ratio
  ]

  # Per-layer stats
  network.layers.each_with_index do |layer, idx|
    stats = stats_per_layer[idx]
    stats.update(layer)

    layer_total = layer.sum(&.processed_count)
    puts "       | Layer[%2d] (n=%4d) => Min: %6d | P50: %6d | P90: %6d | P99: %6d | Max: %6d | μ: %7.1f | σ: %6.1f | Imb: %4.2fx | Count: %8d" % [
      idx, layer.size,
      stats.min, stats.p50, stats.p90, stats.p99, stats.max,
      stats.mean, stats.stddev, stats.imbalance_ratio,
      layer_total
    ]
  end

  puts "-" * 110
end
