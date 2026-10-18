require "spec"
require "option_parser"
require "../src/constant"

describe "CLI Option Parsing" do
  it "falls back to default values from constant.cr when no arguments are provided" do
    network_type = NETWORK_TYPE
    layer_sizes = LAYER_SIZES
    train_samples_count = TRAIN_COUNT
    test_samples_count = TEST_COUNT
    label_filter = nil

    OptionParser.parse([] of String) do |parser|
      parser.on("-n NETWORK_TYPE", "--network_type=NETWORK_TYPE", "") { |n| network_type = n }
      parser.on("-l LAYER_SIZES", "--layer_sizes=LAYER_SIZES", "") do |l|
        layer_sizes = l.split(',').map(&.strip.to_u32)
      end
      parser.on("-t TRAIN_COUNT", "--train_samples_count=TRAIN_COUNT", "") { |t| train_samples_count = t.to_u32 }
      parser.on("-e TEST_COUNT", "--test_samples_count=TEST_COUNT", "") { |e| test_samples_count = e.to_u32 }
      parser.on("-f LABEL_FILTER", "--label_filter=LABEL_FILTER", "") { |f| label_filter = f }
    end

    network_type.should eq(NETWORK_TYPE)
    layer_sizes.should eq(LAYER_SIZES)
    train_samples_count.should eq(TRAIN_COUNT)
    test_samples_count.should eq(TEST_COUNT)
    label_filter.should be_nil
  end

  it "correctly parses custom command-line arguments" do
    network_type = NETWORK_TYPE
    layer_sizes = LAYER_SIZES
    train_samples_count = TRAIN_COUNT
    test_samples_count = TEST_COUNT
    label_filter = nil

    args = ["-n", "accumulator", "-l", "100,50,10", "-t", "50", "-e", "10", "-f", "2"]

    OptionParser.parse(args) do |parser|
      parser.on("-n NETWORK_TYPE", "--network_type=NETWORK_TYPE", "") { |n| network_type = n }
      parser.on("-l LAYER_SIZES", "--layer_sizes=LAYER_SIZES", "") do |l|
        layer_sizes = l.split(',').map(&.strip.to_u32)
      end
      parser.on("-t TRAIN_COUNT", "--train_samples_count=TRAIN_COUNT", "") { |t| train_samples_count = t.to_u32 }
      parser.on("-e TEST_COUNT", "--test_samples_count=TEST_COUNT", "") { |e| test_samples_count = e.to_u32 }
      parser.on("-f LABEL_FILTER", "--label_filter=LABEL_FILTER", "") { |f| label_filter = f }
    end

    network_type.should eq("accumulator")
    layer_sizes.should eq([100_u32, 50_u32, 10_u32])
    train_samples_count.should eq(50_u32)
    test_samples_count.should eq(10_u32)
    label_filter.should eq("2")
  end
end
