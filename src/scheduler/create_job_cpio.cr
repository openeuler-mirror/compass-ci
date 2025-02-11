# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# shellwords require from '/c/lkp-tests/lib/'
require "shellwords"
require "file_utils"
require "json"
require "yaml"

require "./jobfile_operate"

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

      str << "}\n\n"
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
    script_lines << "\n"

    @hash_plain.each { |key, val| parse_one(script_lines, key, val) }
    if hw = self.hw?
      hw.each { |key, val| parse_one(script_lines, key, val) }
    end
    if sv = self.services?
      sv.each { |key, val| parse_one(script_lines, key, val) }
    end

    script_lines << "}\n"

    script_lines.to_s
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
    key.gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m.ord}_" }
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
      return Shellwords.shellescape(val)
    end
  end

  private def parse_one(script_lines, key, val : String)
    return false if !valid_shell_variable?(key)

    value = shell_escape(val)
		script_lines << "\tcheck_set_var #{key}=" + value if value
  end

end

#################################################################################
class Sched
  private def prepare_dir(file_path : String)
    file_path_dir = File.dirname(file_path)
    unless File.exists?(file_path_dir)
      FileUtils.mkdir_p(file_path_dir)
    end
  end

  private def create_job_sh(job_sh_content : String, path : String)
    File.open(path, "w", File::Permissions.new(0o775)) do |file|
      file.puts "#!/bin/sh\n\n"

			file.puts job_sh_content

      file.puts "\"$@\""
    end
  end

  def create_secrets_yaml(job_id, base_dir)
    secrets = @redis.hash_get("id2secrets", job_id)
    unless secrets
      cluster_id = @redis.hash_get("sched/id2cluster", job_id)
      secrets = @redis.hash_get("id2secrets", cluster_id) if cluster_id
    end
    return nil unless secrets

    secrets_yaml = base_dir + "/#{job_id}/secrets.yaml"
    prepare_dir(secrets_yaml)

    File.open(secrets_yaml, "w") do |file|
      YAML.dump(JSON.parse(secrets), file)
    end
  end

  # this depends on LKP_SRC, more exactly
  # - sbin/create-job-cpio.sh
  # - sbin/job2sh and its lib/ depends
  # Normal end users don't need change those logics, so it's enough to
  # use static *mainline* lkp-tests source here instead of per-user
  # uploaded lkp-tests code.
  def create_job_cpio(job : JobHash, base_dir : String)
    create_secrets_yaml(job.id, base_dir)

		job.delete("job2sh")

    # generate job.yaml
    temp_yaml = base_dir + "/#{job.id}/job.yaml"
    prepare_dir(temp_yaml)

    # no change to <object> content { "#! jobs/pixz.yaml": null }
    #  - this will create a <'#! jobs/pixz.yaml':> in the yaml file
    #  - but the orange is <#! jobs/pixz.yaml> in the user job.yaml
    # tested : no effect to job.sh
    File.open(temp_yaml, "w") do |file|
      file.puts(job.to_yaml)
    end

    # generate job.sh
    job_sh = base_dir + "/#{job.id}/job.sh"
    create_job_sh(job.generate_shell_script, job_sh)

    job_dir = base_dir + "/#{job.id}"

    cmd = "./create-job-cpio.sh #{job_dir}"
    idd = `#{cmd}`

    # if the create job cpio failed, what to do?
    puts idd if idd.match(/ERROR/)

    # create result dir and copy job.sh, job.yaml and job.cgz to result dir
    src_dir = File.dirname(temp_yaml)
    dst_dir = File.join("/srv", job.result_root)
    10.times do
      begin
        FileUtils.mkdir_p(dst_dir)
        break
      rescue e
        @log.warn("create result_root dir error, result_root: #{dst_dir} error: #{e.to_s}")
        sleep 1.seconds
      end
    end

    # the job.yaml is not final version
    files = ["#{src_dir}/job.sh",
             "#{src_dir}/job.yaml"]
    FileUtils.cp(files, dst_dir)
  end

end
