# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# shellwords require from '/c/lkp-tests/lib/'
require "shellwords"
require "file_utils"
require "json"
require "yaml"

require "./jobfile_operate"

class Sched
  private def prepare_dir(file_path : String)
    file_path_dir = File.dirname(file_path)
    unless File.exists?(file_path_dir)
      FileUtils.mkdir_p(file_path_dir)
    end
  end

  private def valid_shell_variable?(key)
    key =~ /^[a-zA-Z_]+[a-zA-Z0-9_]*$/
  end

  private def create_job_sh(job_sh_content : Array(JSON::Any), path : String)
    File.open(path, "w", File::Permissions.new(0o775)) do |file|
      file.puts "#!/bin/sh\n\n"

      job_sh_content.each do |line|
        if line.as_a?
          line.as_a.each { |val| file.puts val }
        else
          file.puts line
        end
      end

      file.puts "\"$@\""
    end
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

  private def parse_one(script_lines, key, val)
    return false if val.as_h? || !valid_shell_variable?(key)

    value = shell_escape(val.as_a? || val.to_s)
    script_lines << "\texport #{key}=" + value if value
  end

  private def sh_export_top_env(job_content : Hash)
    script_lines = ["export_top_env()", "{"] of String

    job_content.each { |key, val| parse_one(script_lines, key, val) }

    script_lines << "\n"
    script_lines << "\t[ -n \"$LKP_SRC\" ] ||"
    script_lines << "\texport LKP_SRC=/lkp/${user:-lkp}/src"
    script_lines << "}\n\n"

    script_lines = script_lines.to_s
    script_lines = JSON.parse(script_lines)
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
  def create_job_cpio(job_content : JSON::Any, base_dir : String)
    job_content = job_content.as_h
    create_secrets_yaml(job_content["id"], base_dir)

    # put job2sh in an array
    if job_content.has_key?("job2sh")
      tmp_job_sh_content = job_content["job2sh"]
      job_content.delete("job2sh")

      job_sh_array = [] of JSON::Any
      tmp_job_sh_content.as_h.each do |_key, val|
        next if val == nil
        job_sh_array += val.as_a
      end
    else
      job_sh_array = [] of JSON::Any
    end

    # generate job.yaml
    temp_yaml = base_dir + "/#{job_content["id"]}/job.yaml"
    prepare_dir(temp_yaml)

    # no change to <object> content { "#! jobs/pixz.yaml": null }
    #  - this will create a <'#! jobs/pixz.yaml':> in the yaml file
    #  - but the orange is <#! jobs/pixz.yaml> in the user job.yaml
    # tested : no effect to job.sh
    File.open(temp_yaml, "w") do |file|
      YAML.dump(job_content, file)
    end

    # generate unbroken job shell content
    sh_export_top_env = sh_export_top_env(job_content)
    job_sh_content = sh_export_top_env.as_a + job_sh_array

    # generate job.sh
    job_sh = base_dir + "/#{job_content["id"]}/job.sh"
    create_job_sh(job_sh_content.to_a, job_sh)

    job_dir = base_dir + "/#{job_content["id"]}"

    if job_sh_array.empty?
      lkp_src = Jobfile::Operate.prepare_lkp_tests(job_content["lkp_initrd_user"],
                                  job_content["os_arch"])

      cmd = "#{lkp_src}/sbin/create-job-cpio.sh #{temp_yaml}"
      idd = `#{cmd}`
    else
      cmd = "./create-job-cpio.sh #{job_dir}"
      idd = `#{cmd}`
    end

    # if the create job cpio failed, what to do?
    puts idd if idd.match(/ERROR/)

    # create result dir and copy job.sh, job.yaml and job.cgz to result dir
    src_dir = File.dirname(temp_yaml)
    dst_dir = File.join("/srv", job_content["result_root"].to_s)
    FileUtils.mkdir_p(dst_dir)

    # the job.yaml is not final version
    files = ["#{src_dir}/job.sh",
             "#{src_dir}/job.yaml"]
    FileUtils.cp(files, dst_dir)
  end
end
