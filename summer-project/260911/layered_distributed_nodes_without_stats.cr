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

class LossyMailbox(T, N)
  @buffer : StaticArray(T, N)
  @head   : Int32 = 0
  @tail   : Int32 = 0
  @count  : Int32 = 0
  @dropped : UInt64 = 0_u64

  def initialize(default_val : T)
    @buffer = StaticArray(T, N).new(default_val)
  end

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

  def dispatch_forward(from_node : Node, from_layer_idx : Int32,
                       seq : UInt64, val : Float64,
                       fanout_prob : Float64 = 1.0) : Void
    next_layer = from_layer_idx + 1
    return unless next_layer < @layers.size

    target_nodes = @layers[next_layer]
    return if target_nodes.empty?

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

class Node
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

      while msg = @mailbox.peek
        if now >= msg.deliver_at
          @mailbox.pop
          process(msg)
        else
          break
        end
      end

      if @layer_index < @network.layer_sizes.size - 1
        @local_seq &+= 1_u64
        @network.dispatch_forward(self, @layer_index, @local_seq, @state_accumulator)
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

LAYER_SIZES = [2312, 200, 200, 10]
puts "Initializing layered network fabric: #{LAYER_SIZES.inspect}"
network = LayeredNetworkFabric.new(LAYER_SIZES)

node_id = 0_u32
LAYER_SIZES.each_with_index do |size, layer_idx|
  size.times do
    node = Node.new(node_id, layer_idx, network)
    network.register_node(node, layer_idx)
    node_id &+= 1_u32
  end
end

puts "Total nodes: #{network.all_nodes.size}"
puts "Seeding initial spikes into layer 0..."
layer0 = network.layers[0]

256.times do |i|
  target = layer0[i % layer0.size]
  msg = Message.new(
    0_u16, 0_u32, 1_u64, 1.0,
    Time.instant + LayeredNetworkFabric::TRANSIT_DELAY
  )
  target.receive_message(msg)
end

spawn do
  seq = 0_u64
  loop do
    sleep 2.milliseconds
    seq &+= 1_u64
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

puts "Spawning fibers layer-by-layer..."
network.layers.each_with_index do |layer, layer_idx|
  layer.each do |node|
    spawn do
      Fiber.yield
      node.run
    end
  end
end

maximum = ENV["CRYSTAL_WORKERS"]?.try(&.to_i?) || 4
Fiber::ExecutionContext.default.resize(maximum)

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

  puts "-" * 110
end
