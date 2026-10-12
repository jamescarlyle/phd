record AddressEvent, x : UInt32, y : UInt32, p : UInt32, t : UInt64
record NMnistSample, events : Array(AddressEvent), label : UInt32

module NMnistLoader
  # Helper method for recursive directory traversal.
  private def self.scan_directory(dir : String, all_files : Array({String, UInt32}))
    return unless Dir.exists?(dir)
    Dir.each_child(dir) do |child|
      path = File.join(dir, child)
      if File.directory?(path)
        scan_directory(path, all_files)
      elsif path.ends_with?(".bin")
         parent = File.basename(File.dirname(path))
        if parent.matches?(/^[0-9]$/)
          all_files << {path, parent.to_u32}
        end
      end
    end
  end

  def self.stream_samples(target_dir : String, num_samples : UInt32, channel : Channel(NMnistSample)) : Void
    return if num_samples <= 0
    all_files = [] of {String, UInt32}
    scan_directory(target_dir, all_files)
    return if all_files.empty?

    all_files.shuffle!(Random.new(42))
    files_to_load = all_files.first(num_samples)

    files_to_load.each do |(path, label)|
      events = [] of AddressEvent
      File.open(path, "rb") do |file|
        buffer = Bytes.new(5)
        while file.read_fully?(buffer)
          x = buffer[0].to_u32
          y = buffer[1].to_u32
          p = (buffer[2] >> 7).to_u32
          t = (((buffer[2] & 0x7F).to_u64 << 16) | (buffer[3].to_u64 << 8) | buffer[4].to_u64)
          events << AddressEvent.new(x, y, p, t)
        end
      end
      events.sort_by!(&.t)
      # Pushes sample to channel; fiber suspends if buffer is full.
      channel.send(NMnistSample.new(events, label))
    end
  ensure
    channel.close
  end

  def self.flatten(event : AddressEvent) : UInt32
    (event.p * 34 * 34) + event.y * 34 + event.x
  end

  def self.sample_start_time(sample : NMnistSample) : UInt64
    sample.events[0].t
  end

  def self.sample_end_time(sample : NMnistSample) : UInt64
    sample.events[-1].t
  end
end
