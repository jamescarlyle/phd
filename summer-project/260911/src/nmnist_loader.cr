record AddressEvent, x : Int32, y : Int32, p : Int32, t : Int32
record NMnistSample, events : Array(AddressEvent), label : Int32

module NMnistLoader
  # Helper method for recursive directory traversal.
  private def self.scan_directory(dir : String, all_files : Array({String, Int32}))
    return unless Dir.exists?(dir)
    Dir.each_child(dir) do |child|
      puts child
      path = File.join(dir, child)
      if File.directory?(path)
        scan_directory(path, all_files)
      elsif path.ends_with?(".bin")
        puts path
        parent = File.basename(File.dirname(path))
        puts parent
        if parent.matches?(/^[0-9]$/)
          all_files << {path, parent.to_i}
        end
      end
    end
  end

  def self.load_data(target_dir : String, num_samples : Int32) : Array(NMnistSample)
    puts "Extracting N-MNIST .bin files from #{target_dir}."
    samples = [] of NMnistSample
    if num_samples > 0
      all_files = [] of {String, Int32}
      # Use the helper method instead of a Proc.
      scan_directory(target_dir, all_files)
      puts all_files
      if all_files.empty?
        puts "WARNING: No .bin files found in #{target_dir}."
        return samples
      end
      # Shuffle to ensure a healthy distribution of labels.
      all_files.shuffle!(Random.new(42))
      files_to_load = all_files.first(num_samples)
      puts "Parsing #{files_to_load.size} binary event streams from #{target_dir}."
      files_to_load.each do |(path, label)|
        events = [] of AddressEvent
        File.open(path, "rb") do |file|
          # N-MNIST files are stored as 5-byte chunks.
          buffer = Bytes.new(5)
          while file.read_fully?(buffer)
            # Byte 0: X, Byte 1: Y
            x = buffer[0].to_i32
            y = buffer[1].to_i32
            # Byte 2: Bit 7 is Polarity, Bits 0-6 form the MSB of Timestamp.
            p = (buffer[2] >> 7).to_i32
            # Byte 2 (masked), 3, and 4 form the 23-bit timestamp in microseconds.
            t = (((buffer[2] & 0x7F).to_i32 << 16) | (buffer[3].to_i32 << 8) | buffer[4].to_i32)
            events << AddressEvent.new(x, y, p, t)
          end
        end
        samples << NMnistSample.new(events, label)
      end
    end
    samples
  end
end
