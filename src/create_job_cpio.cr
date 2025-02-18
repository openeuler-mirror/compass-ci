# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "file_utils"
require "process"
require "json"
require "yaml"

require "./lib/jobfile_operate"

# job2sh Key Features:

# 1) Conditional Execution (if statements):
#
#    program:
#      pkgbuild:
#        param1: 100
#        if: [[ "$role" = client ]]
#
#    =>
#    if [[ "$role" = client ]]
#        run_program param1=100 pkgbuild
#    fi

# 2) Pre/Post Scripts:
#
#    program:
#      pkgbuild:
#        pre-script: sleep 1
#        post-script: sleep 2
#
#    =>
#    sleep 1
#    run_program pkgbuild
#    sleep 2

# 3) Environment Variable Handling:
#
#    program:
#      test:
#        iterations: 5
#        mode: "stress test"
#
#    =>
#    run_program iterations=5 mode='stress test' test

class JobHash
  def generate_shell_script
    generate_shell_vars +
    generate_shell_run
  end

  def generate_shell_run
    String.build do |str|
      str << "run_job()\n"
      str << "{\n"
      str << "\techo $$ > $TMP/run-job.pid\n"
      str << "\n"
      str << "\t. $LKP_SRC/lib/http.sh\n"
      str << "\t. $LKP_SRC/lib/job.sh\n"
      str << "\t. $LKP_SRC/lib/env.sh\n"
      str << "\n"

      process_section(str, "setup")
      process_section(str, "daemon")
      process_section(str, "monitor")
      process_section(str, "program")

      str << "}\n"
    end
  end

  def generate_shell_vars
    script_lines = [] of String
    script_lines << "check_set_var()"
    script_lines << "{"
    script_lines << "        local name=\"${1%=*}\""
    script_lines << "        [ -z \"$vars\" -o \"${vars#*$name}\" != \"$vars\" ] && readonly \"$1\""
    script_lines << "}\n"
    script_lines << "read_job_vars()"
    script_lines << "{"
    script_lines << "\tlocal vars=\"$*\""

    @hash_plain.each { |key, val| parse_one(script_lines, key, val) }
    if hw = self.hw?
      hw.each { |key, val| parse_one(script_lines, key, val) }
    end
    if sv = self.services?
      sv.each { |key, val| parse_one(script_lines, key, val) }
    end

    script_lines << "}\n\n"

    script_lines.join("\n")
  end

  private def process_section(str, section)
    return unless entries = @hash_hhh[section]?

    entries.each do |program, config|
      next unless config.is_a?(Hash)

      # Handle pre-script
      if pre_script = config["pre-script"]?
        str << "\t#{pre_script}\n"
      end

      # Handle conditional
      if condition = config["if"]?
        str << "\tif #{condition}\n"
      end

      # Generate command line
      command = build_command(section, program, config)
      str << "\t#{command}\n"

      # Close conditional
      if condition
        str << "\tfi\n"
      end

      # Handle post-script
      if post_script = config["post-script"]?
        str << "\t#{post_script}\n"
      end
    end
  end

  private def build_command(section, program, config)
    command = case section
              when "monitor" then "run_monitor"
              when "setup"   then "run_setup"
              when "daemon"  then "start_daemon"
              when "program" then "run_program"
              else                ""
              end

    # Process environment variables
    env_vars = get_program_env(config)
    env_str = env_vars.map { |k, v| "#{shell_encode_keyword(k)}=#{shell_escape_expand(v)}" }.join(" ")

    # Build command line
    [env_str, command, program].reject(&.empty?).join(" ")
  end

  private def get_program_env(config)
    program_env = {} of String => String
    return program_env unless config.is_a?(Hash)

    config.each do |k, v|
      next if ["if", "if-role", "depends-on", "pre-script", "post-script"].includes?(k)

      case v
      when Hash
        v.each { |sk, sv| program_env[sk.to_s] = sv.to_s }
      else
        program_env[k.to_s] = v.to_s
      end
    end

    program_env
  end

  private def shell_encode_keyword(key)
    key.gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m.codepoints.first}_" }
  end

  private def shell_escape_expand(val)
    case val
    when nil, ""
      ""
    when Int
      val.to_s
    when /^[a-zA-Z0-9_+=:@\/.-]+$/
      val
    else
      "'#{val.gsub("'", "'\"'\"'")}'"
    end
  end

  private def valid_shell_variable?(key)
    key =~ /^[a-zA-Z_]+[a-zA-Z0-9_]*$/
  end

  private def shell_escape(val)
    val = val.join "\n" if val.is_a?(Array)

    if val.nil? || val.empty?
      return nil
    elsif val =~ /^[+-]?([0-9]*\.?[0-9]+|[0-9]+\.?[0-9]*)([eE][+-]?[0-9]+)?$/
      return val
    elsif !val.includes?("'") && !val.includes?("$")
      return "'#{val}'"
    elsif !val.includes?('"')
      return "\"#{val}\""
    else
      return shellescape(val)
    end
  end

  # code copied from Shellwords.shellescape
  private def shellescape(str)
    str = str.to_s

    # An empty argument will be skipped, so return empty quotes.
    return "''".dup if str.empty?

    str = str.dup

    # Treat multibyte characters as is. It is the caller's responsibility
    # to encode the string in the right encoding for the shell
    # environment.
    str = str.gsub(/[^A-Za-z0-9_\-.,:+\/@\n]/, "\\\\\\0")

    # A LF cannot be escaped with a backslash because a backslash + LF
    # combo is regarded as a line continuation and simply ignored.
    str = str.gsub(/\n/, "'\n'")

    str
  end

  private def parse_one(script_lines, key, val : String)
    return false if !valid_shell_variable?(key)

    value = shell_escape(val)
		script_lines << "\tcheck_set_var #{key}=" + value if value
  end

end

#################################################################################
class Sched
  # Save to job_dir, to be picked up by create_job_cpio() at dispatch time.
  # It assumes there is not other scheduler running on other machine.
  def save_secrets(job, job_id)
    secrets = job.hash_hh.delete "secrets"
    return nil unless secrets

    job_dir = File.join(Kemal.config.public_folder, job.id)
    FileUtils.mkdir_p(job_dir)

    secrets_yaml = "#{job_dir}/secrets.yaml"
    File.open(secrets_yaml, "w") do |file|
      YAML.dump(secrets, file)
    end
  end

  def save_job_files(job : JobHash, base_dir : String)
    # Create the job directory
    job_dir = File.join(base_dir, job.id.to_s)
    FileUtils.mkdir_p(job_dir)

    # Remove "job2sh" from the job hash
    job.hash_any.delete("job2sh")

    # Generate job.yaml and job.sh
    job_yaml_path = create_job_yaml(job, job_dir)
    job_sh_path = create_job_sh(job, job_dir)

    # Create CPIO archive
    create_job_cpio(job_dir)

    # Copy job.sh and job.yaml to the result directory
    copy_to_result_root(job, job_yaml_path, job_sh_path)
  end

  def create_job_yaml(job : JobHash, job_dir : String) : String
    job_yaml_path = File.join(job_dir, "job.yaml")
    File.write(job_yaml_path, job.to_yaml)
    job_yaml_path
  end

  def create_job_sh(job : JobHash, job_dir : String) : String
    job_sh_path = File.join(job_dir, "job.sh")

    script_content = <<-SCRIPT
#!/bin/sh

#{job.generate_shell_script}
"$@"
SCRIPT

    File.write(job_sh_path, script_content, perm: 0o775)
    job_sh_path
  end

  # Copy job.sh and job.yaml to the result directory
  def copy_to_result_root(job : JobHash, job_yaml_path : String, job_sh_path : String)
    dst_dir = File.join(BASE_DIR, job.result_root)

    retry_create_dir(dst_dir) &&
    FileUtils.cp([job_sh_path, job_yaml_path], dst_dir)
  end

  private def retry_create_dir(dir : String, max_attempts : Int32 = 10, delay : Time::Span = 1.second)
    max_attempts.times do |attempt|
      begin
        FileUtils.mkdir_p(dir)
        return true
      rescue e
        @log.warn { "Cannot create result_root: #{dir} error: #{e.to_s}" }
        sleep(delay)
      end
    end
    return false
  end

  def create_job_cpio(job_dir : String)
    # Ensure the job directory exists
    unless Dir.exists?(job_dir)
      raise "Directory #{job_dir} does not exist"
    end

    # Find all .sh and .yaml files in the job directory
    files = Dir.glob(["#{job_dir}/*.sh", "#{job_dir}/*.yaml"])

    # Check if there are any files to process
    if files.empty?
      raise "No .sh or .yaml files found in #{job_dir}"
    end

    # Define temporary directory structure
    tmp_dir = File.join(job_dir, ".tmp")
    lkp_dir = File.join(tmp_dir, "lkp", "scheduled")

    # Create necessary directories
    FileUtils.mkdir_p(lkp_dir)

    # Copy files to the temporary directory using hard links
    files.each do |file|
      File.link(file, File.join(lkp_dir, File.basename(file)))
    end

    # Define output .cgz file path
    out_cgz = File.join(job_dir, "job.cgz")

    # Create the .cgz archive
    Dir.cd(tmp_dir) do
      Process.run(
        "find lkp | cpio --quiet -o -H newc | gzip -9 > #{Process.quote(out_cgz)}",
        shell: true
      )
    end

    # Clean up the temporary directory
    FileUtils.rm_rf(tmp_dir)

    # puts "Created #{out_cgz} successfully."
  end

end
