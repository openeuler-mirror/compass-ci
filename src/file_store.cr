
class Job

  def handle_upload_file_store()
    return unless uploads = @hash_hh["upload_file_store"]?

    # Process uploads
    uploads.each do |path, content|
      full_path = File.join(FILE_STORE, path)
      next if File.exists?(full_path)

      dir = File.dirname(full_path)
      FileUtils.mkdir_p(dir) unless Dir.exists?(dir)

      content = Base64.decode_string(content)
      if match = path.match(/-(\h{32})\.cgz$/)
        server_md5 = Digest::MD5.hexdigest(content)
        raise "MD5 mismatch" unless server_md5 == match[1]
      end

      File.write(full_path, content)
    end

    @hash_hh.delete "upload_file_store"
  end

  def handle_need_file_store()
    return unless need_file_store = @hash_array["need_file_store"]?

    # Check required files
    no_file_store = [] of String
    need_file_store.each do |path|
      full_path = File.join(FILE_STORE, path)
      next if File.exists?(full_path)
      if path =~ /^lkp_src\/base\/([\w-]+)\/(\w+)\.cgz$/
        path = create_lkp_base_cgz($2, full_path)
        no_file_store << path if path.is_a?(String)
        next
      end
      no_file_store << path
    end

    if no_file_store.any?
      return {error: "no_file_store", no_file_store: no_file_store}
    end
  end

  def create_lkp_base_cgz(commit : String, full_path : String) : Bool|String
    # Ensure the directory exists
    FileUtils.mkdir_p(File.dirname(full_path))

    lkp_src = ENV["LKP_SRC"]?
    unless lkp_src
      puts "LKP_SRC environment variable is not set."
      return false
    end

    # Check if the commit exists in the repository
    unless commit_exists?(lkp_src, commit)
      new_path = handle_missing_commit(lkp_src, commit)
      return new_path if new_path
    end

    # Run the script to create the LKP CGZ file
    script_path = "#{lkp_src}/sbin/create-lkp-cgz.sh"
    unless File.exists?(script_path)
      puts "Script #{script_path} does not exist."
      return false
    end

    status = Process.run(
      script_path,
      args: [lkp_src, commit, full_path],
    )

    # Check if the script executed successfully
    status.success?
  end

  def handle_missing_commit(lkp_src : String, commit : String) : String?
    puts "Commit #{commit} does not exist. Attempting to pull latest changes..."
    pull_status = Process.run("git", args: ["-C", lkp_src, "pull"])

    unless pull_status.success?
      puts "Failed to pull latest changes from the repository."
      return nil
    end

    unless commit_exists?(lkp_src, commit)
      puts "Commit #{commit} still does not exist after pulling."
      head_commit = get_head_commit(lkp_src)
      unless head_commit
        puts "Failed to retrieve the latest head commit."
        return nil
      end

      # Inform the client to re-submit base+delta based on the new head_commit
      commit_date = get_commit_date(lkp_src, head_commit) # Format: YYYY-MM-DD
      return "lkp_src/base/#{commit_date}/#{head_commit}.cgz"
    end

    nil
  end

  private def commit_exists?(repo_path : String, commit : String) : Bool
    Process.run(
      "git",
      args: ["-C", repo_path, "cat-file", "-e", commit],
    ).success?
  end

  private def get_head_commit(repo_path : String) : String?
    stdout = IO::Memory.new
    process = Process.run("git", args: ["-C", repo_path, "rev-parse", "HEAD"], output: stdout)
    if process.success?
      stdout.to_s.chomp
    else
      puts "Failed to retrieve the head commit."
      nil
    end
  end

  private def get_commit_date(repo_path : String, commit : String) : String?
    stdout = IO::Memory.new
    process = Process.run(
      "git",
      args: ["-C", repo_path, "show", "-s", "--format=%ci", commit],
      output: stdout
    )

    if process.success?
      commit_timestamp = stdout.to_s.chomp
      # Extract YYYY-MM-DD from the commit timestamp (e.g., "2023-10-05 12:34:56 +0000" -> "2023-10-05")
      commit_timestamp[0..9]
    else
      puts "Failed to retrieve commit date for #{commit}."
      nil
    end
  end

end
