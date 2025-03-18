require 'fileutils'
require 'time'

require 'fileutils'
require 'time'

# Constants
MAX_DISK_UTILIZATION = 70
ONE_YEAR_OLD = Time.now - 365 * 24 * 60 * 60

# Function 1: Collect cache dirs from CACHE_DIR
def collect_cache_dirs(cache_dir, find0 = true)
  cache_items = []
  Dir.glob("#{cache_dir}/*").each do |depth_type_dir|
    depth = File.basename(depth_type_dir).to_i
    case depth
    when 0
      cache_items += `find #{depth_type_dir} -type f`.split if find0
    when 1..9
      pattern = "#{depth_type_dir}/" + ("*/" * (depth - 1)) + "*"
      cache_items += Dir.glob(pattern)
    else
      puts "Unknown depth for subdir: #{depth_type_dir}"
    end
  end
  cache_items
end

# Function 2: Collect package files from PACKAGE_CACHE_DIR
def collect_package_files(package_cache_dir)
  package_items = `find #{package_cache_dir} -type f`.split
  package_items
end

# Function 3: Cache modification times and sort items by age
def cache_and_sort_items(items)
  # Create a list of [item, mtime] tuples
  items_with_mtime = items.map { |item| [item, File.mtime(item)] }

  # Sort items by modification time (oldest first)
  items_with_mtime.sort_by! { |_, mtime| mtime }
end

# Function 4: Reclaim items older than 1 year
def reclaim_old_items(items_with_mtime)
  items_with_mtime.delete do |item, mtime|
    if mtime < ONE_YEAR_OLD
      puts "Reclaiming old item: #{mtime} #{item}"
      FileUtils.rm_rf(item)
      true
    else
      break
    end
  end
end

# Function 5: Reclaim items until disk utilization is below 70%
def reclaim_until_disk_util_below_threshold(items_with_mtime, cache_dir)
  loop do
    df_output = `df #{cache_dir}`
    utilization = df_output.split("\n").last.split[4].to_i
    break if utilization < MAX_DISK_UTILIZATION

    # Get the oldest item (first in the sorted list)
    oldest_item, _ = items_with_mtime.first
    if oldest_item
      puts "Reclaiming oldest item: #{mtime} #{oldest_item}"
      FileUtils.rm_rf(oldest_item)
      items_with_mtime.shift # Remove the oldest item from the list
    else
      break
    end
  end
end

# Clean locks older than 1 hour
def reclaim_stale_locks(dir)
  find_command = [
    'find', dir,
    '-name', '*.lock',
    '-type', 'd',
    '-mmin', '+60',
    '-exec', 'rm', '-rf', '{}', '+'
  ]

  # Execute the command safely
  begin
    system(*find_command)
  rescue StandardError => e
    puts "Warning: an error occurred while cleanup stale locks: #{find_command} #{e.message}"
  end
end

# Main function to combine all steps
def reclaim_cache_dirs
  # Collect all items
  cache_items = collect_cache_dirs(ENV["CACHE_DIR"])
  store_items = collect_cache_dirs(ENV["PKG_STORE_DIR"])
  package_items = collect_package_files(ENV["PACKAGE_CACHE_DIR"])
  all_items = cache_items + store_items + package_items

  # Cache modification times and sort items by age
  items_with_mtime = cache_and_sort_items(all_items)

  # Reclaim items older than 1 year
  reclaim_old_items(items_with_mtime)

  # Reclaim items until disk utilization is below 70%
  reclaim_until_disk_util_below_threshold(items_with_mtime, cache_dir)
end
