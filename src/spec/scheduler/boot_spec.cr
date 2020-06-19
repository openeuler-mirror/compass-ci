require "spec"
require "file_utils"

require "kemal"
require "scheduler/scheduler/boot"
require "scheduler/constants.cr"
def create_request_and_return_io_and_context(handler, request)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    context = HTTP::Server::Context.new(request, response)
    handler.call(context)
    response.close
    io.rewind
    {io, context}
end

describe Scheduler::Boot do
    describe "ipxe boot for global" do
        io = IO::Memory.new
        response = HTTP::Server::Response.new(io)
        request = HTTP::Request.new("GET", "/boot.ipxe/mac/52-54-00-12-34-56")
        context = HTTP::Server::Context.new(request, response)

        resources = Scheduler::Resources.new
        it "job content has no os, respon default debian" do
            job_content = JSON.parse(%({"test": "test no os","id": 10}))
            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should contain("debian/aarch64/sid")
        end

        it "job content has os, os_arch, os_version, respon the spliced value" do
            job_content = JSON.parse(%({"id": 10, "os": "openeuler", "os_arch": "aarch64", "os_version": "current"}))
            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")
            os_dir = job_content["os"].to_s.downcase + "/" + job_content["os_arch"].to_s.downcase + "/" + job_content["os_version"].to_s.downcase

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should contain(os_dir)
            respon_list[5].should contain(os_dir)
            respon_list[respon_list.size - 2].should eq("boot")
        end

        it "respon should contain the value of constants.cr" do
            job_content = JSON.parse(DEMO_JOB)
            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")

            respon_list[2].should contain(OS_HTTP_HOST)
            respon_list[2].should contain(OS_HTTP_PORT.to_s)
            respon_list[3].should contain(INITRD_HTTP_HOST)
            respon_list[3].should contain(INITRD_HTTP_PORT.to_s)
            respon_list[4].should contain(SCHED_HOST)
            respon_list[4].should contain(SCHED_PORT.to_s)
            respon_list[5].should contain(OS_HTTP_HOST)
        end

        it "job has program dependence, find and return the initrd path to depends program" do
            job_content = JSON.parse(%({"id": 10, "os": "test", "os_arch": "test", "os_version": "test", "pp": {"want_program": "<want_program> is valid because relate file exist"}}))

            Dir.mkdir_p("/#{ENV["LKP_SRC"]}/distro/depends/")
            File.touch("/#{ENV["LKP_SRC"]}/distro/depends/want_program")
            dir_path = "initrd/deps/test/test/test/"
            Dir.mkdir_p("/srv/#{dir_path}")
            File.touch("/srv/#{dir_path}want_program.cgz")

            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")

            FileUtils.rm_rf("/#{ENV["LKP_SRC"]}/distro/depends/want_program")

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should contain("#{dir_path}want_program.cgz")
        end

        it "job has pkg dependence, find and return the initrd path to depends pkg" do
            job_content = JSON.parse(%({"id": 10, "os": "test", "os_arch": "test", "os_version": "test", "pp": {"want_program": "<want_program> is valid because relate file exist"}}))

            Dir.mkdir_p("/#{ENV["LKP_SRC"]}/pkg/")
            File.touch("/#{ENV["LKP_SRC"]}/pkg/want_program")
            dir_path = "initrd/pkg/test/test/test/"
            Dir.mkdir_p("/srv/#{dir_path}")
            File.touch("/srv/#{dir_path}want_program.cgz")

            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")

            FileUtils.rm_rf("/#{ENV["LKP_SRC"]}/pkg/want_program")

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should contain("#{dir_path}want_program.cgz")
        end

        it "job has program dependence, but not find relate file, ignore it" do
            job_content = JSON.parse(%({"id": 10, "pp": {"want_program": "<want_program> is invalid because relate file not exist"}}))
            respon = Scheduler::Boot.respon(job_content, context, resources)
            respon_list = respon.split("\n")
            file_name = "want_program.cgz"

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should_not contain(file_name)
        end
    end
end
