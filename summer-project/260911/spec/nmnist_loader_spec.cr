require "spec"
require "file_utils"
require "../src/n_mnist_loader"

include NMnistLoader

# Helper to create temporary test fixtures.
module TestFixtures
  def self.create_temp_tree(root : String, files : Array({Int32, String, String, Bytes}))
    Dir.mkdir_p(root)

    files.each do |(label, add_path, filename, data)|
      path = File.join(root, add_path, label.to_s, filename)
      puts path
      # Extract directory containing the file and create it recursively.
      parent_dir = File.dirname(path)
      puts parent_dir
      Dir.mkdir_p(parent_dir)
      puts "wrting file #{path}"
      File.write(path, data)
    end
  end

  def self.cleanup_temp_tree(root : String)
    FileUtils.rm_rf(root) if Dir.exists?(root)
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

  describe "load_data" do
    it "returns empty array when directory does not exist" do
      samples = NMnistLoader.load_data("/nonexistent/path/12345", 10)
      samples.size.should eq(0)
    end

    it "returns empty array when directory is empty" do
      root = "/tmp/nmnist_test_empty"
      begin
        TestFixtures.create_temp_tree(root, [] of {Int32, String, String, Bytes})
        samples = NMnistLoader.load_data(root, 10)
        samples.size.should eq(0)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "ignores non-.bin files" do
      root = "/tmp/nmnist_test_nonbin"
      begin
        files = [
          {3, "", "sample.txt", Bytes.new(0)},
          {3, "", "data.bin", Bytes.new(0)},
        ]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })
        samples = NMnistLoader.load_data(root, 10)
        samples.size.should eq(1)
        samples[0].label.should eq(3)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "ignores files in non-digit parent directories" do
      root = "/tmp/nmnist_test_nondigit"
      begin
        files = [
          {10, "", "sample.bin", Bytes.new(0)},  # parent "10" -> ignored
          {3, "", "data.bin", Bytes.new(0)},     # parent "3" -> accepted
        ]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 10)
        samples.size.should eq(1)
        samples[0].label.should eq(3)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "discovers files recursively" do
      root = "/tmp/nmnist_test_recursive"
      begin
        files = [
          {0, "", "a.bin", Bytes.new(0)},
          {1, "sub/", "b.bin", Bytes.new(0)},
          {2, "sub/deep/", "c.bin", Bytes.new(0)},
        ]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 10)
        labels = samples.map(&.label).sort!
        labels.should eq([0, 1, 2])
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "limits number of samples to num_samples" do
      root = "/tmp/nmnist_test_limit"
      begin
        files = (0...10).map { |i| {i % 10, "", "sample#{i}.bin", Bytes.new(0)} }
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 3)
        samples.size.should eq(3)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles num_samples greater than available files" do
      root = "/tmp/nmnist_test_overlimit"
      begin
        files = [
          {1, "", "a.bin", Bytes.new(0)},
          {2, "", "b.bin", Bytes.new(0)},
        ]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 100)
        samples.size.should eq(2)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "decodes a single event correctly" do
      root = "/tmp/nmnist_test_single_event"
      begin
        event_data = TestFixtures.make_file([{10, 20, 1, 12345}])
        files = [{7, "", "event.bin", event_data}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 1)
        samples.size.should eq(1)
        samples[0].label.should eq(7)
        samples[0].events.size.should eq(1)

        ev = samples[0].events[0]
        ev.x.should eq(10)
        ev.y.should eq(20)
        ev.p.should eq(1)
        ev.t.should eq(12345)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "decodes multiple events in order" do
      root = "/tmp/nmnist_test_multi_event"
      begin
        events = [
          {0, 0, 0, 0},
          {1, 1, 1, 100},
          {34, 56, 0, 999999},
        ]
        event_data = TestFixtures.make_file(events)
        files = [{4, "", "multi.bin", event_data}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 1)
        samples.size.should eq(1)
        samples[0].events.size.should eq(3)

        events.each_with_index do |(ex, ey, ep, et), i|
          ev = samples[0].events[i]
          ev.x.should eq(ex)
          ev.y.should eq(ey)
          ev.p.should eq(ep)
          ev.t.should eq(et)
        end
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles maximum 23-bit timestamp" do
      root = "/tmp/nmnist_test_max_ts"
      begin
        max_ts = (1 << 23) - 1  # 8388607
        event_data = TestFixtures.make_file([{0, 0, 0, max_ts}])
        files = [{0, "", "max_ts.bin", event_data}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 1)
        samples[0].events[0].t.should eq(max_ts)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles polarity 0 and 1 correctly" do
      root = "/tmp/nmnist_test_polarity"
      begin
        events = [
          {0, 0, 0, 0},
          {0, 0, 1, 1},
        ]
        event_data = TestFixtures.make_file(events)
        files = [{5, "", "polarity.bin", event_data}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 1)
        samples[0].events[0].p.should eq(0)
        samples[0].events[1].p.should eq(1)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "produces deterministic selection with seed 42" do
      root = "/tmp/nmnist_test_deterministic"
      begin
        files = (0...20).map { |i| {i % 10, "", "s#{i}.bin", Bytes.new(0)} }
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples1 = NMnistLoader.load_data(root, 10)
        samples2 = NMnistLoader.load_data(root, 10)

        samples1.map(&.label).should eq(samples2.map(&.label))
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles truncated file (incomplete 5-byte record)" do
      root = "/tmp/nmnist_test_truncated"
      begin
        # Create a file with 7 bytes (one complete event + 2 extra bytes)
        events = [
          {0, 0, 0, 0},
          {0, 0, 1, 1},
        ]
        event_data = TestFixtures.make_file(events)
        truncated = event_data[0..6]  # 7 bytes
        files = [{3, "", "truncated.bin", truncated}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, 1)
        samples.size.should eq(1)
        samples[0].events.size.should eq(1)  # Only complete record decoded
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles num_samples == 0" do
      root = "/tmp/nmnist_test_zero"
      begin
        files = [{1, "", "a.bin", Bytes.new(0)}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })
        samples = NMnistLoader.load_data(root, 0)
        samples.size.should eq(0)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end

    it "handles negative num_samples" do
      root = "/tmp/nmnist_test_negative"
      begin
        files = [{1, "", "a.bin", Bytes.new(0)}]
        TestFixtures.create_temp_tree(root, files.map { |f| {f[0], f[1], f[2], f[3]} })

        samples = NMnistLoader.load_data(root, -5)
        samples.size.should eq(0)
      ensure
        TestFixtures.cleanup_temp_tree(root)
      end
    end
  end
end
