record AddressEvent, x : UInt16, y : UInt16, p : UInt16, t : UInt64
record DatasetSample, events : Array(AddressEvent), label : UInt8

module NMnistLoader
  # Helper method for recursive directory traversal.
  private def self.scan_directory(dir : String, all_files : Array({String, UInt8}))
    return unless Dir.exists?(dir)
    Dir.each_child(dir) do |child|
      path = File.join(dir, child)
      if File.directory?(path)
        scan_directory(path, all_files)
      elsif path.ends_with?(".bin")
         parent = File.basename(File.dirname(path))
        if parent.matches?(/^[0-9]$/)
          all_files << {path, parent.to_u8}
        end
      end
    end
  end

  def self.stream_samples(target_dir : String, num_samples : UInt32, channel : Channel(DatasetSample)) : Void
    return if num_samples <= 0
    all_files = [] of {String, UInt8}
    scan_directory(target_dir, all_files)
    return if all_files.empty?

    all_files.shuffle!(Random.new(42))
    files_to_load = all_files.first(num_samples)

    files_to_load.each do |(path, label)|
      events = [] of AddressEvent
      File.open(path, "rb") do |file|
        buffer = Bytes.new(5)
        while file.read_fully?(buffer)
          x = buffer[0].to_u16
          y = buffer[1].to_u16
          p = (buffer[2] >> 7).to_u16
          t = (((buffer[2] & 0x7F).to_u64 << 16) | (buffer[3].to_u64 << 8) | buffer[4].to_u64)
          events << AddressEvent.new(x, y, p, t)
        end
      end
      events.sort_by!(&.t)
      # Pushes sample to channel; fiber suspends if buffer is full.
      channel.send(DatasetSample.new(events, label))
    end
  ensure
    channel.close
  end

  def self.flatten(event : AddressEvent) : UInt16
    (event.p * 34 * 34) + event.y * 34 + event.x
  end

  def self.sample_start_time(sample : DatasetSample) : UInt64
    sample.events[0].t
  end

  def self.sample_end_time(sample : DatasetSample) : UInt64
    sample.events[-1].t
  end
end

module MnistLoader
  WIDTH = 28
  HEIGHT = 28
  INPUT_SIZE = WIDTH * HEIGHT
  DURATION_US = 350_000_u64
  MAX_RATE_HZ = 100.0
  SEED = 42

  # Exactly the same argument types and return type as NMnistLoader.
  # target_dir contains exactly one uncompressed IDX image/label pair.
  def self.stream_samples(target_dir : String, num_samples : UInt32,
                          channel : Channel(DatasetSample)) : Void
    return if num_samples == 0

    image_path, label_path = dataset_paths(target_dir)
    File.open(image_path, "rb") do |images|
      File.open(label_path, "rb") do |labels|
        image_magic = images.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        image_count = images.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        rows = images.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        columns = images.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        label_magic = labels.read_bytes(UInt32, IO::ByteFormat::BigEndian)
        label_count = labels.read_bytes(UInt32, IO::ByteFormat::BigEndian)

        raise ArgumentError.new("Invalid image IDX magic") unless image_magic == 2051
        raise ArgumentError.new("Invalid label IDX magic") unless label_magic == 2049
        raise ArgumentError.new("MNIST images must be 28x28") unless rows == HEIGHT && columns == WIDTH
        raise ArgumentError.new("Image/label counts differ") unless image_count == label_count
        expected_images = 16_i64 + image_count.to_i64 * INPUT_SIZE
        expected_labels = 8_i64 + label_count.to_i64
        raise ArgumentError.new("Invalid image file length") unless images.size == expected_images
        raise ArgumentError.new("Invalid label file length") unless labels.size == expected_labels

        indices = Array(UInt32).new(image_count.to_i, &.to_u32)
        indices.shuffle!(Random.new(SEED))
        pixels = Bytes.new(INPUT_SIZE)
        indices.first(num_samples.to_i).each do |index|
          images.seek(16_i64 + index.to_i64 * INPUT_SIZE)
          images.read_fully(pixels)
          labels.seek(8_i64 + index.to_i64)
          label = labels.read_bytes(UInt8)
          raise ArgumentError.new("MNIST label must be in 0..9") if label > 9

          # Per-image RNG keeps encoding independent of selection order/count.
          rng = Random.new(SEED.to_u64 + index.to_u64)
          events = encode(pixels, rng)
          channel.send(DatasetSample.new(events, label))
        end
      end
    end
  ensure
    channel.close
  end

  # Independent homogeneous Poisson process for each nonzero pixel.
  # Exponential intervals are calculated in seconds, then converted to us.
  def self.encode(pixels : Bytes, rng : Random = Random.new(SEED)) : Array(AddressEvent)
    raise ArgumentError.new("Expected 784 pixels") unless pixels.size == INPUT_SIZE
    events = [] of AddressEvent
    duration_s = DURATION_US.to_f64 / 1_000_000.0
    pixels.each_with_index do |intensity, index|
      next if intensity == 0
      rate_hz = MAX_RATE_HZ * intensity.to_f64 / 255.0
      time_s = 0.0
      loop do
        # next_float is in [0, 1); 1-u is in (0, 1].
        time_s += -Math.log(1.0 - rng.next_float) / rate_hz
        break if time_s >= duration_s
        timestamp = (time_s * 1_000_000.0).to_u64
        next if timestamp >= DURATION_US
        events << AddressEvent.new((index % WIDTH).to_u16,
          (index // WIDTH).to_u16, 0_u16, timestamp)
      end
    end
    events.sort_by! { |event| {event.t, event.y, event.x} }
    events
  end

  def self.flatten(event : AddressEvent) : UInt16
    (event.y.to_u32 * WIDTH + event.x).to_u16
  end

  def self.sample_start_time(sample : DatasetSample) : UInt64
    0_u64
  end

  def self.sample_end_time(sample : DatasetSample) : UInt64
    DURATION_US
  end

  private def self.dataset_paths(target_dir : String) : Tuple(String, String)
    pairs = [
      {"train-images-idx3-ubyte", "train-labels-idx1-ubyte"},
      {"t10k-images-idx3-ubyte", "t10k-labels-idx1-ubyte"},
      {"train-images.idx3-ubyte", "train-labels.idx1-ubyte"},
      {"t10k-images.idx3-ubyte", "t10k-labels.idx1-ubyte"},
    ]
    found = pairs.compact_map do |pair|
      image = File.join(target_dir, pair[0])
      label = File.join(target_dir, pair[1])
      {image, label} if File.file?(image) && File.file?(label)
    end
    raise ArgumentError.new("No complete uncompressed MNIST IDX pair in #{target_dir}") if found.empty?
    raise ArgumentError.new("Ambiguous MNIST directory: separate train and test pairs") if found.size > 1
    found[0]
  end
end
