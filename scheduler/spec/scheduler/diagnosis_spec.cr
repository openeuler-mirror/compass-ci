require "spec"

require "../../src/scheduler/diagnosis"
require "../../lib/kemal/src/kemal/ext/response"

describe Scheduler::Diagnosis do

    describe "resource maintain" do
        it "connection test scuess" do
            io = IO::Memory.new
            response = HTTP::Server::Response.new(io)
            headers = HTTP::Headers { "content" => "application/json" }
            body = { :test => "1234" }.to_json
            request = HTTP::Request.new("POST", "/queues", headers, body)
            context = HTTP::Server::Context.new(request, response)

            resources = Scheduler::Resources.new
            resources.qos(2, 2)
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9200)

            respon = Scheduler::Diagnosis.test(context, resources)
            (respon =~ /Error reading socket/).should be_nil
            (respon =~ /Error connecting to:/).should be_nil
        end

        it "connection fail to elasticsearch" do
            io = IO::Memory.new
            response = HTTP::Server::Response.new(io)
            headers = HTTP::Headers { "content" => "application/json" }
            body = { :test => "1234" }.to_json
            request = HTTP::Request.new("POST", "/queues", headers, body)
            context = HTTP::Server::Context.new(request, response)

            resources = Scheduler::Resources.new
            resources.qos(2, 2)
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9300)

            respon = Scheduler::Diagnosis.test(context, resources)
            # match start at elasticsearch:\n
            (respon =~ /Error reading socket/).should_not be_nil
        end

        it "connection fail to redis" do
            io = IO::Memory.new
            response = HTTP::Server::Response.new(io)
            headers = HTTP::Headers { "content" => "application/json" }
            body = { :test => "1234" }.to_json
            request = HTTP::Request.new("POST", "/queues", headers, body)
            context = HTTP::Server::Context.new(request, response)

            resources = Scheduler::Resources.new
            resources.qos(2, 2)
            resources.redis_client("localhost", 6370)
            resources.es_client("localhost", 9200)

            respon = Scheduler::Diagnosis.test(context, resources)
            (respon =~ /Error connecting to 'localhost:6370':/).should_not be_nil
        end
    end

end
