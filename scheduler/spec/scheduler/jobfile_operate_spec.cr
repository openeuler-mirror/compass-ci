require "spec"
require "../../src/constants"
require "../../src/jobfile_operate"

describe Jobfile::Operate do

    describe "update" do
        file_path = "test/update.yaml"
        section = "#! job"
        kv = {"id" => "123456"}

        Jobfile::Operate.prepare_dir(file_path)
        if File.exists?(file_path)
            FileUtils.rm(file_path)
        end

        it "When no find, then append at end" do
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

        it "When find, then replace it" do
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

        it "When no find, but find section, then append in the section" do
            File.open(file_path, "w") do |f|
                f.puts("#! job/")
                f.puts("#! other")
            end
            Jobfile::Operate.update(file_path, section, kv)

            line_index = 0
            File.each_line(file_path) do |line|
                match_info = line.match(/id: (.*)/)
                line_index = line_index +1
                if match_info
                    break
                end
            end

            line_index.should eq(2)
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

            line_index = 0
            File.each_line(file_path) do |line|
                match_info = line.match(/id: (.*)/)
                line_index = line_index +1
                if match_info
                    break
                end
            end

            line_index.should eq(3)
            FileUtils.rm(file_path)
        end

    end

    describe "create_job_cpio" do
        # when debug this,it seems to execute "chmod +x /c/lkp-tests/sbin/create-job-cpio.sh" to get permission
        it "from jobid create job.cgz" do
            job_id = "100"
            resources = Scheduler::Resources.new
            resources.es_client(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            fs_root = File.real_path(".")
            resources.fsdir_root("#{fs_root}/public")
            resources.@es_client.not_nil!.add("/jobs/job", JSON.parse(DEMO_JOB).as_h, job_id)

            oldfile = ::File.join [resources.@fsdir_root, job_id]
            FileUtils.rm_r(oldfile) if File.exists?(oldfile)

            Jobfile::Operate.create_job_cpio(JSON.parse(DEMO_JOB), resources.@fsdir_root.not_nil!)
            (File.exists?(::File.join [resources.@fsdir_root, job_id, "job.cgz"])).should be_true
        end
    end
end
