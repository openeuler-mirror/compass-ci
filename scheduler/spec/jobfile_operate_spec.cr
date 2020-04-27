require "spec"
require "../src/jobfile_operate"

describe Jobfile::Operate do

    describe "update" do
        file_path = "test/update.yaml"
        section = "#! job"
        kv = {"id" => "123456"}

        Jobfile::Operate.prepareDir(file_path)
        if File.exists?(file_path)
            FileUtils.rm(file_path)
        end

        it "When nofind , then append at end" do
            File.open(file_path, "w") do |f|
                f.close()
            end

            Jobfile::Operate.update(file_path, section, kv)

            linepre = ""
            File.each_line(file_path) do |line|
                linepre = line
            end
            linepre.should eq("#{kv.first_key}: #{kv[kv.first_key]}")
            FileUtils.rm(file_path)
        end

        it "When find , then replace it" do
            File.open(file_path, "w") do |f|
                f.puts("id: 000000")
            end
            Jobfile::Operate.update(file_path, section, kv)

            linepre = ""
            File.each_line(file_path) do |line|
                match_info = line.match(/id: (.*)/)
                if match_info
                    linepre = "id: #{match_info.[1]}" 
                end
            end

            linepre.should eq("#{kv.first_key}: #{kv[kv.first_key]}")
            FileUtils.rm(file_path)
        end

        it "When nofind, but find section, then append in the section" do
            File.open(file_path, "w") do |f|
                f.puts("#! job/")
                f.puts("#! other")
            end
            Jobfile::Operate.update(file_path, section, kv)

            lineIndex = 0
            File.each_line(file_path) do |line|
                match_info = line.match(/id: (.*)/)
                lineIndex = lineIndex +1
                if match_info
                    break
                end
            end

            lineIndex.should eq(2)
            FileUtils.rm(file_path)
        end

        # is this the real specification?
        it "When find key & section, but they are not matched, ignore now" do
            File.open(file_path, "w") do |f|
                f.puts("#! job")
                f.puts("#! other")
                f.puts("id: 000000")
            end
            Jobfile::Operate.update(file_path, section, kv)

            lineIndex = 0
            File.each_line(file_path) do |line|
                match_info = line.match(/id: (.*)/)
                lineIndex = lineIndex +1
                if match_info
                    break
                end
            end

            lineIndex.should eq(3)
            FileUtils.rm(file_path)
        end

    end

    describe "createJobPackage" do
        it "from jobid create job.cgz" do
            job_id = "testjob"
            resources = Scheduler::Resources.new
            resources.es_client("localhost", 9200)
            resources.fsdir_root("/home/chief/code/crcode/scheduler/public")
            json = JSON.parse(Jobfile::Operate.load_yaml("test/demo_job.yaml").to_json)
            resources.@es_client.not_nil!.add("/jobs/job", json.as_h, job_id)

            FileUtils.rm_r(::File.join [resources.@fsdir_root, job_id])

            Jobfile::Operate.createJobPackage(job_id, resources)
            (File.exists?(::File.join [resources.@fsdir_root, job_id, "job.cgz"])).should be_true
        end
    end
end
  
