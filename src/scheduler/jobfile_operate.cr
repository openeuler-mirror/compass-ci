# SPDX-License-Identifier: MulanPSL-2.0+

require "file_utils"
require "json"
require "yaml"

# require from '/c/lkp-tests/lib/'
require "shellwords"

if ENV["LKP_SRC"] != "/c/lkp-tests"
  raise "ENV LKP_SRC mismatch: #{ENV["LKP_SRC"]} '/c/lkp-tests'"
end

module Jobfile::Operate

    def self.prepare_dir(file_path : String)
        file_path_dir = File.dirname(file_path)
        if !File.exists?(file_path_dir)
            FileUtils.mkdir_p(file_path_dir)
        end
    end

    def self.valid_shell_variable?(key)
          key =~ /^[a-zA-Z_]+[a-zA-Z0-9_]*$/
    end

    def self.create_job_sh(job_sh_content : Array(JSON::Any), path : String)
      File.open(path, "w", File::Permissions.new(0o775)) do |file|
        file.puts "#!/bin/sh\n\n"
        job_sh_content.each do |line|
          if line.as_a?
            line.as_a.each {|val| file.puts val}
          else
            file.puts line
          end
        end
        file.puts "\"$@\""
      end
    end

    def self.shell_escape(val)
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

    def self.parse_one(script_lines, key, val)
        if valid_shell_variable?(key)
            if val.as_h?
                return false
            end
            if val.as_a?
              value = shell_escape(val.as_a)
            else
                value = shell_escape(val.to_s)
            end
            script_lines << "\texport #{key}=" + value if value
        end
    end

    def self.sh_export_top_env(job_content : Hash)
        script_lines = ["export_top_env()", "{"] of String

        job_content.each {|key, val| parse_one(script_lines, key, val)}

        script_lines << "\n"
        script_lines << "\t[ -n \"$LKP_SRC\" ] ||"
        script_lines << "\texport LKP_SRC=/lkp/${user:-lkp}/src"
        script_lines << "}\n\n"

        script_lines = "#{script_lines}"
        script_lines = JSON.parse(script_lines)
    end

    def self.create_job_cpio(job_content : JSON::Any, base_dir : String)
        job_content = job_content.as_h

        # put job2sh in an array
        if job_content.has_key?("job2sh")
            tmp_job_sh_content = job_content["job2sh"]

            job_sh_array = [] of JSON::Any
            tmp_job_sh_content.as_h.each do |_key, val|
                job_sh_array += val.as_a
            end
        else
            job_sh_array = [] of JSON::Any
        end

        # generate job.yaml
        temp_yaml = base_dir + "/" +  job_content["id"].to_s + "/job.yaml"
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
        job_sh = base_dir + "/" +  job_content["id"].to_s + "/job.sh"
        create_job_sh(job_sh_content.to_a, job_sh)

        job_dir = base_dir + "/" +  job_content["id"].to_s

        if job_sh_array.empty?
            lkp_src = prepare_lkp_tests(job_content["lkp_initrd_user"],
                                        job_content["os_arch"])

            cmd = "#{lkp_src}/sbin/create-job-cpio.sh #{temp_yaml}"
            idd = `#{cmd}`
        else
            cmd ="./create-job-cpio.sh #{job_dir}"
            idd = `#{cmd}`
        end

        # if the create job cpio failed, what to do?
        if idd.match(/ERROR/)
            puts idd
        end
        # create result dir and copy job.sh, job.yaml and job.cgz to result dir
        src_dir = File.dirname(temp_yaml)
        dst_dir = job_content["result_root"].to_s
        FileUtils.mkdir_p(dst_dir)
        # the job.yaml is not final version
        files = ["#{src_dir}/job.sh",
                 "#{src_dir}/job.yaml",
                 "#{src_dir}/job.cgz"]
        FileUtils.cp(files, dst_dir)
    end

    def self.unzip_cgz(source_path : String, target_path : String)
        FileUtils.mkdir_p(target_path)
        cmd = "cd #{target_path};gzip -dc #{source_path}|cpio -id"
        system cmd
    end

    def self.prepare_lkp_tests(lkp_initrd_user = "latest", os_arch = "aarch64")
        expand_dir_base = File.expand_path(Kemal.config.public_folder +
                                           "/expand_cgz")
        FileUtils.mkdir_p(expand_dir_base)

        # update lkp-xxx.cgz if they are different
        target_path = update_lkp_when_different(expand_dir_base,
                                                lkp_initrd_user,
                                                os_arch)

        # delete oldest lkp, if exists too much
        del_lkp_if_too_much(expand_dir_base)

        return "#{target_path}/lkp/lkp/src"
    end

    # list *.cgz (lkp initrd), sorted in reverse time order
    # and delete 10 oldest cgz file, when exists more than 100
    # also delete the DIR expand from the cgz file
    def self.del_lkp_if_too_much(base_dir)
        file_list = `ls #{base_dir}/*.cgz -tr`
        file_array = file_list.split("\n")
        if file_array.size > 100
            10.times do |index|
                FileUtils.rm_rf(file_array[index])
                FileUtils.rm_rf(file_array[index].chomp(".cgz"))
            end
        end
    end

    def self.update_lkp_when_different(base_dir, lkp_initrd_user, os_arch)
        target_path = base_dir + "/#{lkp_initrd_user}-#{os_arch}"
        bak_lkp_filename = target_path + ".cgz"
        source_path = "/srv/initrd/lkp/#{lkp_initrd_user}/lkp-#{os_arch}.cgz"

        if File.exists?(bak_lkp_filename)
            # no need update
            return target_path if FileUtils.cmp(source_path, bak_lkp_filename)

            # remove last expanded lkp initrd DIR
            FileUtils.rm_rf(target_path)
        end

        # bakup user lkp-xxx.cgz (for next time check)
        FileUtils.cp(source_path, bak_lkp_filename)
        unzip_cgz(bak_lkp_filename, target_path)
        return target_path
    end

    def self.auto_submit_job(job_file, overide_parameter)
        cmd = "#{ENV["LKP_SRC"]}/sbin/submit SCHED_HOST=localhost"
        cmd += " SCHED_PORT=#{ENV["SCHED_PORT"]}"
        cmd += " -s '#{overide_parameter}' #{job_file}"
        puts `#{cmd}`
    end
end
