require "spec"

require "kemal"
require "scheduler/scheduler/boot"

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
    end
end
