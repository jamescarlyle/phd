require "./data_loader"

abstract class LoaderAdapter
  abstract def stream_samples(
    target_dir : String,
    num_samples : UInt32,
    channel : Channel(DatasetSample)
  ) : Void

  abstract def flatten(event : AddressEvent) : UInt16
  abstract def sample_start_time(sample : DatasetSample) : UInt64
  abstract def sample_end_time(sample : DatasetSample) : UInt64

  abstract def input_size : UInt32

  abstract def target_path(
    base_dir : String,
    label_filter : String?
  ) : String

  def self.build(dataset_type : String) : LoaderAdapter
    case dataset_type.downcase
    when "nmnist"
      NMnistLoaderAdapter.new
    when "mnist"
      MnistLoaderAdapter.new
    else
      raise ArgumentError.new(
        "Unknown dataset type: #{dataset_type}; expected mnist or nmnist"
      )
    end
  end
end

class NMnistLoaderAdapter < LoaderAdapter
  def stream_samples(
    target_dir : String,
    num_samples : UInt32,
    channel : Channel(DatasetSample)
  ) : Void
    NMnistLoader.stream_samples(target_dir, num_samples, channel)
  end

  def flatten(event : AddressEvent) : UInt16
    NMnistLoader.flatten(event)
  end

  def sample_start_time(sample : DatasetSample) : UInt64
    NMnistLoader.sample_start_time(sample)
  end

  def sample_end_time(sample : DatasetSample) : UInt64
    NMnistLoader.sample_end_time(sample)
  end

  def input_size : UInt32
    2 * 34 * 34
  end

  def target_path(
    base_dir : String,
    label_filter : String?
  ) : String
    label_filter ? File.join(base_dir, label_filter) : base_dir
  end
end

class MnistLoaderAdapter < LoaderAdapter
  def stream_samples(
    target_dir : String,
    num_samples : UInt32,
    channel : Channel(DatasetSample)
  ) : Void
    MnistLoader.stream_samples(target_dir, num_samples, channel)
  end

  def flatten(event : AddressEvent) : UInt16
    MnistLoader.flatten(event)
  end

  def sample_start_time(sample : DatasetSample) : UInt64
    MnistLoader.sample_start_time(sample)
  end

  def sample_end_time(sample : DatasetSample) : UInt64
    MnistLoader.sample_end_time(sample)
  end

  def input_size : UInt32
    28 * 28
  end

  def target_path(
    base_dir : String,
    label_filter : String?
  ) : String
    unless label_filter.nil?
      raise ArgumentError.new(
        "Label filtering is not implemented for the MNIST IDX loader"
      )
    end

    base_dir
  end
end
