# Prompt:
# You are helping me generate a voltage waveform definition for a probe station controlled via Keysight EasyExpert. The waveform is a repeating “pulse block” train with separate “rest blocks”. I want a small Crystal program that:
# Takes command‑line parameters:
# id – initial 0 V delay before the first pulse block’s rest segment (time with suffix, e.g. 20u for 20 µs).
# rd – rest duration inside each pulse block (time with suffix, e.g. 20m for 20 ms).
# rv – rest voltage (V, e.g. 0.1).
# pd – pulse segment duration (rise + flat + fall) within each pulse block (time with suffix, e.g. 1m for 1 ms).
# pv – pulse voltage (V, e.g. 0.5).
# pr – pulse rise time (time with suffix, e.g. 10n for 10 ns).
# pf – pulse fall time (time with suffix, e.g. 10n).
# pc – number of pulses (integer, e.g. 2).
# rc – number of rest blocks (integer, e.g. 2).
# output – filename for the EasyExpert CSV (optional, default "waveform.csv").
# Time suffixes supported: s, ms, us/u, ns/n, m (milli).
# Uses this timing model:
# Each pulse block has duration rd + pd:
# Rest segment: duration rd, voltage rv.
# Pulse segment: total duration pd, split into:
# Rise: pr (from rv to pv),
# Flat: pd - pr - pf (at pv),
# Fall: pf (from pv back to rv).
# Each rest block has the same duration as a pulse block (rd + pd), but is at constant voltage rv (no pulse).
# The overall sequence is:
# Start at t = 0, v = 0.
# Initial delay id at 0 V.
# At t = id, step to rv.
# Then for each pulse block:
# Rest segment (rd) at rv.
# Pulse segment (pd): rise, flat, fall.
# Between pulse blocks, insert rest blocks as needed so that the total number of rest blocks equals rc. For pc = 2, rc = 2, this means:
# One rest segment inside the first pulse block.
# One additional rest block between the two pulses.
# No extra trailing rest blocks beyond that.
# All event times are integer nanoseconds; no rounding is needed if the arithmetic is done in seconds then converted via t_ns = t_s * 1e9.
# Produces two outputs:
# Terminal output: one line per segment boundary, in the format:
# time_s,voltage
# First line must be 0,0.0.
# For id=20u rd=20m rv=0.1 pd=1m pv=0.5 pr=10n pf=10n pc=2 rc=2, there should be exactly 10 lines with voltages in this sequence:
# 0.0
# 0.1 (end of initial delay, step to rest voltage)
# 0.1 (end of first rest segment)
# 0.5 (end of first rise)
# 0.5 (end of first flat)
# 0.1 (end of first fall)
# 0.1 (end of second rest block)
# 0.5 (end of second rise)
# 0.5 (end of second flat)
# 0.1 (end of second fall)
# EasyExpert CSV file:
# Filename from output parameter (default waveform.csv).
# CSV with header: Time (s),Voltage (V).
# One row per terminal output line, with time in seconds (time_s / 1e9) and the same voltage.
# This file must be suitable for direct import into Keysight EasyExpert as a voltage vs time waveform.
# Prints a brief summary to stderr (not stdout), including:
# All input parameters.
# Derived values: pulse_flat = pd - pr - pf, pulse_block_duration = rd + pd, rest_block_duration = rd + pd.
# Total number of points and final time in ns.
# The CSV filename written.
# Implementation constraints:
# Language: Crystal.
# Single file, no external dependencies.
# Robust parsing of time suffixes.
# Validate that pd >= pr + pf; if not, print an error to stderr and exit with non‑zero status.
# Keep stdout strictly to the time_s,voltage lines so it can be redirected or parsed cleanly.
# Parameter example:
# id=20u rd=20m rv=0.1 pd=1m pv=0.5 pr=10n pf=10n pc=2 rc=2

# Generates:
#   1) Terminal output: one line per segment boundary, "time_s,voltage"
#   2) EasyExpert direct import CSV: "Time (s),Voltage (V)"
#
# Timing model:
#   - Pulse block duration = rd + pd
#   - Within each pulse block:
#       * rest segment: duration = rd, voltage = rv
#       * pulse segment: total duration = pd, split into:
#           - rise: pr
#           - flat: pd - pr - pf
#           - fall: pf
#   - Rest block duration = pulse block duration = rd + pd
#
# Sequence for pc=2, rc=2 (10 points):
#   0: t=0,                     v=0.0
#   1: t=id,                    v=rv
#   2: t=id+rd,                 v=rv
#   3: t=id+rd+pr,              v=pv
#   4: t=id+rd+pr+(pd-pr-pf),   v=pv
#   5: t=id+rd+pd,              v=rv
#   6: t=id+rd+pd + (rd+pd),    v=rv
#   7: t=... + pr,              v=pv
#   8: t=... + pr + (pd-pr-pf), v=pv
#   9: t=... + pd,              v=rv
#
# Usage:
#   crystal run voltage_train_eex.cr -- \
#     id=20u rd=20m rv=0.1 pd=1m pv=0.5 pr=10n pf=10n pc=2 rc=2 \
#     output=waveform.csv
#
# Parameters:
#   id  : initial 0V delay (seconds, with suffix)
#   rd  : rest duration inside each pulse block (seconds, with suffix)
#   rv  : rest voltage (V)
#   pd  : pulse segment duration (rise+flat+fall) (seconds, with suffix)
#   pv  : pulse voltage (V)
#   pr  : pulse rise time (seconds, with suffix)
#   pf  : pulse fall time (seconds, with suffix)
#   pc  : pulse count (integer)
#   rc  : rest block count (integer)
#   output : EasyExpert CSV filename (default: "waveform.csv")
def parse_time_with_suffix(str : String) : Float64
  s = str.strip.downcase
  num_str = s.match(/^([+-]?\d+(\.\d+)?)/)
  raise ArgumentError.new("Invalid number in: #{str}") unless num_str
  num = num_str[0].to_f
  suffix = s[num_str[0].size..-1]
  factor = case suffix
           when "", "s" then 1.0
           when "ms" then 1e-3
           when "us", "u" then 1e-6
           when "ns", "n" then 1e-9
           when "m" then 1e-3
           else
             raise ArgumentError.new("Unknown time suffix in: #{str}")
           end
  num * factor
end
def format_value_with_suffix(value : Float64) : String
  # Convert to nanoseconds as an integer
  nano_value = (value * 1_000_000_000).round.to_i64
  case
  when nano_value % 1_000_000_000 == 0
    "#{nano_value // 1_000_000_000}"
  when nano_value % 1_000_000 == 0
    "#{nano_value // 1_000_000}m"
  when nano_value % 1_000 == 0
    "#{nano_value // 1_000}u"
  else
    "#{nano_value}n"
  end
end
def main
  args = ARGV.each_with_object({} of String => String) do |arg, h|
    k, v = arg.split("=", 2)
    h[k] = v
  end
  required = %w[id rd rv pd pv pr pf pc rc]
  missing = required - args.keys
  if !missing.empty?
    puts "Missing parameters: #{missing.join(", ")}"
    exit 1
  end
  id = parse_time_with_suffix(args["id"])
  rd = parse_time_with_suffix(args["rd"])
  rv = args["rv"].to_f
  pd = parse_time_with_suffix(args["pd"])
  pv = args["pv"].to_f
  pr = parse_time_with_suffix(args["pr"])
  pf = parse_time_with_suffix(args["pf"])
  pc = args["pc"].to_i
  rc = args["rc"].to_i
  output = args["output"]?
  # Derived durations
  pulse_flat = pd - pr - pf
  if pulse_flat < 0
    puts "Error: pd must be >= pr + pf (got pd=#{pd}, pr=#{pr}, pf=#{pf})"
    exit 1
  end
  pulse_block_duration = rd + pd
  rest_block_duration = pulse_block_duration
  first_measurement = id + pr + (rd * 0.05)
  measurement_period = pulse_block_duration
  measurement_duration = rd * 0.9
  points = Array({Float64, Float64}).new
  t = 0.0
  # 0: start at 0V.
  points << {t, 0.0}
  # End of initial delay: step to rest voltage.
  t += id
  points << {t, 0.0}
  # Add rising time.
  t += pr
  points << {t, rv}
  # Pulse loop.
  pc.times do
    # Rest.
    t += rd
    points << {t, rv}
    # rise
    t += pr
    points << {t, pv}
    # flat
    t += pulse_flat
    points << {t, pv}
    # fall
    t += pf
    points << {t, rv}
  end
  # Rest loop.
  rc.times do
    # Rest.
    t += rd
    points << {t, rv}
  end

  # Terminal output: time_s,voltage
  points.each do |(time_s, v)|
    puts "#{sprintf("%.9f", time_s)},#{v}"
  end
  if output
    # EasyExpert CSV: Time (s), Voltage (V)
    File.open(output, "w") do |file|
      file.puts "Time (s),Voltage (V)"
      points.each do |(time_s, v)|
        file.puts "#{time_s},#{v}"
      end
    end
  end
  # Summary to stderr
  puts
  puts "Summary:"
  puts "Initial delay = #{format_value_with_suffix(id)}s"
  puts "Rest duration = #{args["rd"]}s"
  puts "Rest voltage = #{args["rv"]}V"
  puts "Pulse duration = #{args["pd"]}s"
  puts "Pulse voltage = #{args["pv"]}V"
  puts "Pulse rise = #{args["pr"]}s"
  puts "Pulse fall = #{args["pf"]}s"
  puts "Rest cycles = #{args["rc"]}"
  puts "Pulse cycles = #{args["pc"]}"
  puts "Pulse block duration = #{format_value_with_suffix(pulse_block_duration)}s"
  puts "Rest block duration = #{format_value_with_suffix(rest_block_duration)}s"
  puts "Measurement points = #{rc + pc}"
  puts "First measurement time = #{format_value_with_suffix(first_measurement)}s"
  puts "Measurement period = #{format_value_with_suffix(measurement_period)}s"
  puts "Measurement duration = #{format_value_with_suffix(measurement_duration)}s"
  puts "Total elapsed time = #{format_value_with_suffix(t)}s"
  puts "EasyExpert CSV written to: #{output}"
end
main
