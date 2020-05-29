require "file_utils"
require "json"
require "yaml"

require  "./scheduler/resources"

module Jobfile::Operate

    def self.update(filePath : String, section : String, kv : Hash)
        sectionFind = -1
        kvFind = false
        kv_key = kv.first_key

        jobArray = File.read_lines(filePath)
        jobArray.each_index do |index|
            line = jobArray[index]
            match_info = line.match(/#{kv_key}: (.*)/)
            if match_info
                line = line.sub("#{match_info[1]}", kv[kv_key])
                jobArray[index] = line
                kvFind = true
                break
            elsif line.match(/#{section}/)
                sectionFind = index
            end
        end

        if !kvFind    #append at the end or after the section
            appendInfo = "#{kv_key}: #{kv[kv_key]}"
            if sectionFind == -1
                jobArray << appendInfo
            else
                jobArray.insert(sectionFind+1, appendInfo)
            end
        end

        File.open(filePath, "w") do |f|
            jobArray.each do |line|
                f.puts(line)
            end
        end

    end

    def self.prepareDir(filePath : String)
        filePathDir = File.dirname(filePath)
        if !File.exists?(filePathDir)
            FileUtils.mkdir_p(filePathDir)
        end
    end
    
    def self.create_job_cpio(job_content : JSON::Any, base_dir : String)
	temp_yaml = base_dir + "/" +  job_content["_id"].to_s + "/job.yaml"
        prepareDir(temp_yaml)

        # no change to <object> content { "#! jobs/pixz.yaml": null }
        #  - this will create a <'#! jobs/pixz.yaml':> in the yaml file
        #  - but the orange is <#! jobs/pixz.yaml> in the user job.yaml
        # tested : no effect to job.sh
        File.open(temp_yaml, "w") do |file|
            YAML.dump(job_content, file)
        end

        cmd = "./create-job-cpio.sh #{temp_yaml}"
        idd = `#{cmd}`

        # if the create job cpio failed, what to do?
        if idd.match(/ERROR/)
            puts idd
        end
    end
      
    def self.load_yaml(filePath : String)
        yaml =  File.open(filePath) do |file|
            YAML.parse(file)
        end
    end
end
