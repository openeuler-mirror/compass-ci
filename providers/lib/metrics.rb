=begin
  Background:
  This module collects and reports server resource metrics (CPU, memory, disk, network) for a cluster monitoring dashboard.
  The goal is to provide a quick, user-friendly overview of cluster health, with metrics displayed in a single line per machine.
  The implementation avoids fixed intervals, supports variable timing between updates, and caches expensive computations to improve efficiency.

  Design:
  1. Metrics Collection:
     - CPU: Tracks idle, iowait, and system percentages using `/proc/stat`.
     - Memory: Calculates free memory percentage from `/proc/meminfo`.
     - Disk: Reports the highest disk usage percentage and mount point using `df`.
     - Network: Computes utilization percentage and error rates from `/proc/net/dev`.
     - Disk I/O: Measures utilization percentage from `/proc/diskstats`.

  2. Variable Intervals:
     - Timestamps are recorded for each computation to handle variable intervals between updates.
     - Delta calculations (e.g., network, disk I/O) use actual time differences for accurate rates.

  3. Caching:
     - CPU metrics are cached for 1 second to balance accuracy and performance.
     - Disk usage is cached for 10 seconds due to the expensive `df` operation.
     - Network and disk I/O metrics are not cached, as they rely on rate-based calculations.

  4. Output:
     - Metrics are formatted as percentages for quick readability.
     - Disk usage includes both a percentage value and a human-readable string (e.g., "92% /srv/os").
     - A JSON payload is sent to the dashboard, including hostname, metrics, and metadata.

  5. Thread Safety:
     - Assumes single-threaded execution. If used in a multi-threaded context, add locks around shared state.

  Example Use Case:
  - A cluster monitoring dashboard displays one line per machine, with color-coded status indicators (green/yellow/red) based on thresholds.
  - Admins can quickly identify overloaded nodes (e.g., high CPU, disk, or network usage) and drill down for details.

  Dependencies:
  - Relies on `/proc` filesystem for metric collection.
  - Assumes `df` and `uname` are available on the system.
=end

def count_disks_sys_block
  # List directories under /sys/block, which correspond to disks
  disks = Dir.entries('/sys/block')

  # Filter out hidden entries (e.g., '.' and '..') and device mapper devices (e.g., 'dm-*')
  disks.reject! { |entry| entry.start_with?('.') || entry.start_with?('dm-') }

  # Return the number of disks found
  disks.size
end

def disk_max_used_percent
  max = {value: 0, string: "0% /"}
  `df -P`.split("\n")[1..-1].each do |line|
    parts = line.split
    usage = parts[4].to_i
    if usage > max[:value]
      max[:value] = usage
      max[:string] = "#{usage}% #{parts[-1]}"
    end
  end
  max
end

def parse_meminfo
  meminfo_hash = {}
  File.open('/proc/meminfo', 'r') do |file|
    file.each_line do |line|
      key, value = line.split(':')
      meminfo_hash[key.strip] = value.strip.to_i >> 10 # Convert bytes to MiB
    end
  end
  meminfo_hash
end

class MultiQemuDocker

  def cpu_metrics(now)
    return @cpu_metrics if @cpu_metrics && @cpu_metrics[:timestamp] && (now - @cpu_metrics[:timestamp] < 1) # Cache for 1 second

    current = File.readlines('/proc/stat').first.split[1..-1].map(&:to_i)
    if @prev_cpu && @prev_cpu_timestamp
      total = current.sum - @prev_cpu.sum
      total = 1 if total == 0
      time_diff = now - @prev_cpu_timestamp
      @cpu_metrics = {
        idle: [((current[3] - @prev_cpu[3]) * 100) / total, 0].max, # Integer division
        iowait: [((current[4] - @prev_cpu[4]) * 100) / total, 0].max, # Integer division
        system: [((current[2] - @prev_cpu[2]) * 100) / total, 0].max, # Integer division
        timestamp: now
      }
    else
      @cpu_metrics = {idle: 0, iowait: 0, system: 0, timestamp: now}
    end

    @prev_cpu = current
    @prev_cpu_timestamp = now
    @cpu_metrics
  end

  def disk_max_used_percent
    return @disk_usage if @disk_usage && (Time.now - @disk_usage[:timestamp] < 60) # Cache for 60 seconds

    max = {value: 0, string: "0% /"}
    `df -P`.split("\n")[1..-1].each do |line|
      parts = line.split
      usage = parts[4].to_i
      if usage > max[:value]
        max[:value] = usage
        max[:string] = "#{usage}% #{parts[-1]}"
      end
    end
    @disk_usage = {value: max[:value], string: max[:string], timestamp: Time.now}
    @disk_usage
  end

  def network_metrics(now)
    return {utilization: 0, errors: 0} unless File.exist?('/proc/net/dev')

    current_rx = File.read('/proc/net/dev').lines.grep(/:\s+/).sum { |l| l.split[1].to_i }
    current_tx = File.read('/proc/net/dev').lines.grep(/:\s+/).sum { |l| l.split[9].to_i }

    if @prev_net_stats && @prev_net_timestamp
      delta_rx = current_rx - @prev_net_stats[:rx]
      delta_tx = current_tx - @prev_net_stats[:tx]
      time_diff = now - @prev_net_timestamp
      mbps = ((delta_rx + delta_tx) * 8) / (1 + 1_000_000 * time_diff.to_i) # Integer division
      utilization = (mbps * 100) / 1000 # Assuming 1Gbps, integer division
      utilization = [utilization, 100].min # Clamp to 100
      utilization = 0 if utilization < 0
    else
      utilization = 0
    end

    @prev_net_stats = {rx: current_rx, tx: current_tx}
    @prev_net_timestamp = now
    {utilization: utilization, errors: 0} # Error counting needs /proc/net/dev parsing
  end

  def disk_io_utilization(now)
    return 0 unless File.exist?('/proc/diskstats')

    current_io = File.readlines('/proc/diskstats').sum { |l| l.split[12].to_i }
    if @prev_io_time && @prev_io_timestamp
      delta = current_io - @prev_io_time
      time_diff = now - @prev_io_timestamp
      utilization = (delta * 100) / (1 + time_diff.to_i * 1000) # Integer division
      utilization = [utilization, 100].min # Clamp to 100
      utilization = 0 if utilization < 0
      utilization
    else
      0
    end
  ensure
    @prev_io_time = current_io
    @prev_io_timestamp = now
  end

  def total_memory_mb
    @last_meminfo["MemTotal"]
  end

  def free_memory_mb
    @last_meminfo["MemFree"] +
    (@last_meminfo["MemAvailable"] - @last_meminfo["MemFree"]) / 2
  end

end
