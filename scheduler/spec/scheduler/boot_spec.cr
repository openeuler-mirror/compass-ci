require "spec"

require "kemal"
require "../../src/scheduler/boot"

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
        it "job_id = 0, respon no job" do
            io = IO::Memory.new
            response = HTTP::Server::Response.new(io)
            request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")
            context = HTTP::Server::Context.new(request, response)
            resources = Scheduler::Resources.new

            respon = Scheduler::Boot.respon("0", context, resources)
            respon.should eq("#!ipxe\n\necho ...\necho No job now\necho ...\nreboot\n")
        end

        it "job_id != 0, respon initrd kernel job in .cgz file" do
            kemal = Kemal::RouteHandler::INSTANCE
            kemal.add_route "GET", "/boot.:boot_type/:parameter/:value" do |env|
            end
            request = HTTP::Request.new("GET", "/boot.ipxe/mac/52%3A54%3A00%3A12%3A34%3A56")

            context = create_request_and_return_io_and_context(kemal, request)[1]
            url_params = Kemal::ParamParser.new(request, context.route_lookup.params).url
            # url_params => {"boot_type" => "ipxe", "parameter" => "mac", "value" => "52:54:00:12:34:56"}

            resources = Scheduler::Resources.new

            respon = Scheduler::Boot.respon("1", context, resources)
            respon_list = respon.split("\n")

            respon_list[0].should eq("#!ipxe")
            respon_list[2].should start_with("initrd")
            respon_list[respon_list.size - 2].should eq("boot")
        end
    end
end
