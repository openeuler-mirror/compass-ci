require "file_utils"
require "json"
require "yaml"

require  "./scheduler/resources"

module Jobfile::Operate

    def self.update(file_path : String, section : String, kv : Hash)
        section_find = -1
        kv_find = false
        kv_key = kv.first_key

        job_array = File.read_lines(file_path)
        job_array.each_index do |index|
            line = job_array[index]
            match_info = line.match(/#{kv_key}: (.*)/)
            if match_info
                line = line.sub("#{match_info[1]}", kv[kv_key])
                job_array[index] = line
                kv_find = true
                break
            elsif line.match(/#{section}/)
                section_find = index
            end
        end

        if !kv_find    #append at the end or after the section
            append_info = "#{kv_key}: #{kv[kv_key]}"
            if section_find == -1
                job_array << append_info
            else
                job_array.insert(section_find + 1, append_info)
            end
        end

        File.open(file_path, "w") do |f|
            job_array.each do |line|
                f.puts(line)
            end
        end

    end

    def self.prepare_dir(file_path : String)
        file_path_dir = File.dirname(file_path)
        if !File.exists?(file_path_dir)
            FileUtils.mkdir_p(file_path_dir)
        end
    end
    def self.create_job_cpio(job_content : JSON::Any, base_dir : String)
        temp_yaml = base_dir + "/" +  job_content["id"].to_s + "/job.yaml"
        prepare_dir(temp_yaml)

        # no change to <object> content { "#! jobs/pixz.yaml": null }
        #  - this will create a <'#! jobs/pixz.yaml':> in the yaml file
        #  - but the orange is <#! jobs/pixz.yaml> in the user job.yaml
        # tested : no effect to job.sh
        File.open(temp_yaml, "w") do |file|
            YAML.dump(job_content, file)
        end

        cmd = "#{ENV["LKP_SRC"]}/sbin/create-job-cpio.sh #{temp_yaml}"
        idd = `#{cmd}`

        # if the create job cpio failed, what to do?
        if idd.match(/ERROR/)
            puts idd
        end
        # create result_root and copy job.cgz to result_root
        FileUtils.mkdir_p("#{job_content["result_root"]}")
        FileUtils.cp("#{File.dirname(temp_yaml)}/job.cgz", "#{job_content["result_root"]}/job.cgz")
    end
    def self.load_yaml(file_path : String)
        File.open(file_path) do |file|
            YAML.parse(file)
        end
    end
end
