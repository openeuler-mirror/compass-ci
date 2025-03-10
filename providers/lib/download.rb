
def symlink_resource(url, symlink_path)
  # Parse the URL and extract the path
  uri = URI.parse(url)
  global_file_path = uri.path

  my_file_path = global_file_path.sub(%r{^/srv}, BASE_DIR)
  if File.exist?(my_file_path)
    FileUtils.ln_s(my_file_path, symlink_path, force: true)
    puts "Symlink created at:\n#{symlink_path} =>\n#{my_file_path}"
    return true
  elsif !IS_ROOT_USER
    if File.exist?(global_file_path)
      FileUtils.ln_s(global_file_path, symlink_path, force: true)
      puts "Symlink created at:\n#{symlink_path} =>\n#{global_file_path}"
      return true
    end
  end
  return false
end

def download_resource(url)
  # Extract the path from the URL
  if url =~ /\/job.cgz$/
    local_path = "#{ENV["host_dir"]}/job.cgz" # no need caching
  else
    local_path = "#{ENV["DOWNLOAD_DIR"]}#{URI.parse(url).path}"
  end

  # Skip download if the file already exists
  if File.exist?(local_path)
    return local_path
  end

  # Create the directory structure if it doesn't exist
  FileUtils.mkdir_p(File.dirname(local_path))

  return local_path if symlink_resource(url, local_path)

  # Download the file with wget
  success = system("wget --timeout=30 --tries=3 -nv -a #{ENV['log_file'].shellescape} -O #{local_path.shellescape} #{url.shellescape}")

  # Raise an error if the download fails
  raise ResourceError, "Failed to download #{url}" unless success

  return local_path
end

