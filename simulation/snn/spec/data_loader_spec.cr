require "spec"
require "file_utils"
require "../src/data_loader"

include NMnistLoader

# Helper to create temporary test fixtures.
module TestFixtures
  def self.create_temp_tree(root_dir : String, files : Array({Int32, String, String, Bytes}))
    Dir.mkdir_p(root_dir)

    files.each do |(label, add_path, filename, data)|
      path = File.join(root_dir, add_path, label.to_s, filename)
      # Extract directory containing the file and create it recursively.
      parent_dir = File.dirname(path)
      Dir.mkdir_p(parent_dir)
      File.write(path, data)
    end
  end

  def self.cleanup_temp_tree(root_dir : String)
    FileUtils.rm_rf(root_dir) if Dir.exists?(root_dir)
  end

  def self.make_event(x : Int32, y : Int32, p : Int32, t : Int32) : Bytes
    buffer = Bytes.new(5)
    buffer[0] = x.to_u8
    buffer[1] = y.to_u8
    buffer[2] = (((p & 0x01) << 7) | ((t >> 16) & 0x7F)).to_u8
    buffer[3] = ((t >> 8) & 0xFF).to_u8
    buffer[4] = (t & 0xFF).to_u8
    buffer
  end

  def self.make_file(events : Array({Int32, Int32, Int32, Int32})) : Bytes
    io = IO::Memory.new
    events.each do |(x, y, p, t)|
      io.write(make_event(x, y, p, t))
    end
    io.to_slice
  end
end

describe NMnistLoader do
  describe "SampleLoader.stream_samples" do
    it "returns empty array when directory does not exist" do
      channel = Channel(DatasetSample).new
      received_samples = [] of DatasetSample
      non_existent_dir = "/nonexistent/path/12345"
      spawn do
        NMnistLoader.stream_samples(non_existent_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.should be_empty
    end

    it "returns empty array when directory is empty" do
      root_dir = "/tmp/nmnist_test_empty"
      channel = Channel(DatasetSample).new
      received_samples = [] of DatasetSample
      TestFixtures.create_temp_tree(root_dir, [] of {Int32, String, String, Bytes})
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.should be_empty
    end
  end

  it "ignores non-.bin files" do
    root_dir = "/tmp/nmnist_test_nonbin"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = [
        {3, "", "sample.txt", Bytes.new(0)},
        {3, "", "data.bin", Bytes.new(0)},
      ]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(1)
      received_samples[0].label.should eq(3)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "ignores files in non-digit parent directories" do
    root_dir = "/tmp/nmnist_test_nondigit"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = [
        {10, "", "sample.bin", Bytes.new(0)},  # parent "10" -> ignored
        {3, "", "data.bin", Bytes.new(0)},     # parent "3" -> accepted
      ]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(1)
      received_samples[0].label.should eq(3)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "discovers files recursively" do
    root_dir = "/tmp/nmnist_test_recursive"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = [
        {0, "", "a.bin", Bytes.new(0)},
        {1, "sub/", "b.bin", Bytes.new(0)},
        {2, "sub/deep/", "c.bin", Bytes.new(0)},
      ]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      labels = received_samples.map(&.label).sort!
      labels.should eq([0, 1, 2])
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "limits number of samples to num_samples" do
    root_dir = "/tmp/nmnist_test_limit"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = (0...10).map { |i| {i % 10, "", "sample#{i}.bin", Bytes.new(0)} }
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 3, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(3)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "handles num_samples greater than available files" do
    root_dir = "/tmp/nmnist_test_overlimit"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = [
        {1, "", "a.bin", Bytes.new(0)},
        {2, "", "b.bin", Bytes.new(0)},
      ]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 100, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(2)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "decodes a single event correctly" do
    root_dir = "/tmp/nmnist_test_single_event"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      event_data = TestFixtures.make_file([{10, 20, 1, 12345}])
      files = [{7, "", "event.bin", event_data}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 100, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(1)
      received_samples[0].label.should eq(7)
      received_samples[0].events.size.should eq(1)

      ev = received_samples[0].events[0]
      ev.x.should eq(10)
      ev.y.should eq(20)
      ev.p.should eq(1)
      ev.t.should eq(12345)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "decodes multiple events in order" do
    root_dir = "/tmp/nmnist_test_multi_event"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      events = [
        {0, 0, 0, 0},
        {1, 1, 1, 100},
        {34, 56, 0, 999999},
      ]
      event_data = TestFixtures.make_file(events)
      files = [{4, "", "multi.bin", event_data}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 1, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(1)
      received_samples[0].events.size.should eq(3)
      events.each_with_index do |(ex, ey, ep, et), i|
        ev = received_samples[0].events[i]
        ev.x.should eq(ex)
        ev.y.should eq(ey)
        ev.p.should eq(ep)
        ev.t.should eq(et)
      end
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "handles maximum 23-bit timestamp" do
    root_dir = "/tmp/nmnist_test_max_ts"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      max_ts = (1 << 23) - 1  # 8388607
      event_data = TestFixtures.make_file([{0, 0, 0, max_ts}])
      files = [{0, "", "max_ts.bin", event_data}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 1, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples[0].events[0].t.should eq(max_ts)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "handles polarity 0 and 1 correctly" do
    root_dir = "/tmp/nmnist_test_polarity"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      events = [
        {0, 0, 0, 0},
        {0, 0, 1, 1},
      ]
      event_data = TestFixtures.make_file(events)
      files = [{5, "", "polarity.bin", event_data}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 1, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples[0].events[0].p.should eq(0)
      received_samples[0].events[1].p.should eq(1)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "produces deterministic selection with seed 42" do
    root_dir = "/tmp/nmnist_test_deterministic"
    channel = Channel(DatasetSample).new
    received_samples1 = [] of DatasetSample
    received_samples2 = [] of DatasetSample
    begin
      files = (0...20).map { |i| {i % 10, "", "s#{i}.bin", Bytes.new(0)} }
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples1 << sample
      end
      channel = Channel(DatasetSample).new
      spawn do
        NMnistLoader.stream_samples(root_dir, 10, channel)
      end
      while sample = channel.receive?
        received_samples2 << sample
      end
      received_samples1.map(&.label).should eq(received_samples2.map(&.label))
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "handles truncated file (incomplete 5-byte record)" do
    root_dir = "/tmp/nmnist_test_truncated"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      # Create a file with 7 bytes (one complete event + 2 extra bytes)
      events = [
        {0, 0, 0, 0},
        {0, 0, 1, 1},
      ]
      event_data = TestFixtures.make_file(events)
      truncated = event_data[0..6]  # 7 bytes
      files = [{3, "", "truncated.bin", truncated}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 1, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(1)
      received_samples[0].events.size.should eq(1)  # Only complete record decoded
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  it "handles num_samples == 0" do
    root_dir = "/tmp/nmnist_test_zero"
    channel = Channel(DatasetSample).new
    received_samples = [] of DatasetSample
    begin
      files = [{1, "", "a.bin", Bytes.new(0)}]
      TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
      spawn do
        NMnistLoader.stream_samples(root_dir, 0, channel)
      end
      while sample = channel.receive?
        received_samples << sample
      end
      received_samples.size.should eq(0)
    ensure
      TestFixtures.cleanup_temp_tree(root_dir)
    end
  end

  # TODO sort out negative samples
  # it "handles negative num_samples" do
  #   root_dir = "/tmp/nmnist_test_negative"
  #   channel = Channel(DatasetSample).new
  #   received_samples = [] of DatasetSample
  #   begin
  #     files = [{1, "", "a.bin", Bytes.new(0)}]
  #     TestFixtures.create_temp_tree(root_dir, files.map { |f| {f[0], f[1], f[2], f[3]} })
  #     spawn do
  #       NMnistLoader.stream_samples(root_dir, -5_u, channel)
  #     end
  #     while sample = channel.receive?
  #       received_samples << sample
  #     end
  #     received_samples.size.should eq(0)
  #   ensure
  #     TestFixtures.cleanup_temp_tree(root_dir)
  #   end
  # end
end

private def with_mnist_fixture(pixels : Array(Bytes), labels : Array(UInt8), & : String ->)
  dir = File.join(Dir.tempdir, "mnist-spec-#{Random::Secure.hex(12)}")
  Dir.mkdir_p(dir)
  begin
    File.open(File.join(dir, "train-images-idx3-ubyte"), "wb") do |io|
      [2051_u32, pixels.size.to_u32, 28_u32, 28_u32].each do |value|
        io.write_bytes(value, IO::ByteFormat::BigEndian)
      end
      pixels.each { |image| io.write(image) }
    end
    File.open(File.join(dir, "train-labels-idx1-ubyte"), "wb") do |io|
      [2049_u32, labels.size.to_u32].each do |value|
        io.write_bytes(value, IO::ByteFormat::BigEndian)
      end
      labels.each { |label| io.write_byte(label) }
    end
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

# A concurrent consumer is necessary: send blocks on an unbuffered channel.
# Producer errors are captured and re-raised in the spec fiber.
private def collect_mnist(dir : String, count : UInt32) : Array(DatasetSample)
  channel = Channel(DatasetSample).new
  completion = Channel(Exception?).new(1)
  spawn do
    begin
      MnistLoader.stream_samples(dir, count, channel)
      completion.send(nil)
    rescue ex
      completion.send(ex)
    end
  end
  samples = [] of DatasetSample
  while sample = channel.receive?
    samples << sample
  end
  if error = completion.receive
    raise error
  end
  samples
end

describe MnistLoader do
  it "maps coordinates onto a single 784-neuron input plane" do
    MnistLoader.flatten(AddressEvent.new(0_u16, 0_u16, 0_u16, 0_u64)).should eq(0_u16)
    MnistLoader.flatten(AddressEvent.new(27_u16, 27_u16, 0_u16, 0_u64)).should eq(783_u16)
  end

  it "produces no spikes for black pixels and supports an empty sample" do
    events = MnistLoader.encode(Bytes.new(784, 0_u8))
    events.should be_empty
    sample = DatasetSample.new(events, 0_u8)
    MnistLoader.sample_start_time(sample).should eq(0_u64)
    MnistLoader.sample_end_time(sample).should eq(MnistLoader::DURATION_US)
  end

  it "rejects an incorrect pixel count" do
    expect_raises(ArgumentError, "Expected 784 pixels") do
      MnistLoader.encode(Bytes.new(783))
    end
  end

  it "encodes reproducible, sorted events within the observation window" do
    pixels = Bytes.new(784, 255_u8)
    first = MnistLoader.encode(pixels, Random.new(42))
    first.should eq(MnistLoader.encode(pixels, Random.new(42)))
    first.should_not be_empty
    first.map(&.t).should eq(first.map(&.t).sort!)
    first.each do |event|
      event.x.should be < 28_u16
      event.y.should be < 28_u16
      event.p.should eq(0_u16)
      event.t.should be < MnistLoader::DURATION_US
    end
  end

  it "emits spikes only at active pixel coordinates" do
    pixels = Bytes.new(784, 0_u8)
    pixels[2 * 28 + 3] = 255_u8
    events = MnistLoader.encode(pixels)
    events.should_not be_empty
    events.each do |event|
      event.x.should eq(3_u16)
      event.y.should eq(2_u16)
    end
  end

  it "has a population spike count consistent with the configured rates" do
    # 784 independent processes provide a stable aggregate test.
    bright = MnistLoader.encode(Bytes.new(784, 255_u8)).size
    dim = MnistLoader.encode(Bytes.new(784, 128_u8)).size
    expected = 784 * MnistLoader::MAX_RATE_HZ * MnistLoader::DURATION_US / 1_000_000.0
    (bright.to_f64 / expected).should be_close(1.0, 0.05)
    (dim.to_f64 / bright).should be_close(128.0 / 255.0, 0.05)
  end

  it "reads paired labels and images without replacement and caps the count" do
    black = Bytes.new(784, 0_u8)
    white = Bytes.new(784, 255_u8)
    with_mnist_fixture([black, white], [3_u8, 7_u8]) do |dir|
      samples = collect_mnist(dir, 10_u32)
      samples.map(&.label).sort!.should eq([3_u8, 7_u8])
      samples.find! { |sample| sample.label == 3 }.events.should be_empty
      samples.find! { |sample| sample.label == 7 }.events.should_not be_empty
      samples.should eq(collect_mnist(dir, 10_u32))
      collect_mnist(dir, 1_u32).should eq(samples.first(1))
    end
  end

  it "closes the channel on a zero-count request without opening files" do
    channel = Channel(DatasetSample).new
    MnistLoader.stream_samples("/unused", 0_u32, channel)
    channel.closed?.should be_true
    channel.receive?.should be_nil
  end

  it "raises and closes the channel when no IDX pair exists" do
    with_mnist_fixture([] of Bytes, [] of UInt8) do |dir|
      File.delete(File.join(dir, "train-labels-idx1-ubyte"))
      channel = Channel(DatasetSample).new
      expect_raises(ArgumentError, /No complete/) do
        MnistLoader.stream_samples(dir, 1_u32, channel)
      end
      channel.closed?.should be_true
    end
  end

  it "rejects mismatched counts" do
    with_mnist_fixture([Bytes.new(784)], [] of UInt8) do |dir|
      expect_raises(ArgumentError, "Image/label counts differ") { collect_mnist(dir, 1_u32) }
    end
  end

  it "rejects truncated image data before sending any samples" do
    with_mnist_fixture([Bytes.new(783)], [0_u8]) do |dir|
      expect_raises(ArgumentError, "Invalid image file length") { collect_mnist(dir, 1_u32) }
    end
  end

  it "rejects invalid labels" do
    with_mnist_fixture([Bytes.new(784)], [10_u8]) do |dir|
      expect_raises(ArgumentError, "MNIST label must be in 0..9") { collect_mnist(dir, 1_u32) }
    end
  end

  it "rejects invalid magic values" do
    with_mnist_fixture([Bytes.new(784)], [0_u8]) do |dir|
      File.open(File.join(dir, "train-images-idx3-ubyte"), "r+") do |io|
        io.write_bytes(0_u32, IO::ByteFormat::BigEndian)
      end
      expect_raises(ArgumentError, "Invalid image IDX magic") { collect_mnist(dir, 1_u32) }
    end
  end
end
