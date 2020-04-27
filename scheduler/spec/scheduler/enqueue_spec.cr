require "spec"

require "../../src/redis_client"
require "../../src/scheduler/enqueue"
require "../../lib/kemal/src/kemal/ext/response"
require "../../lib/kemal/src/kemal/ext/context"

def createPostContext(hash : Hash)
    io = IO::Memory.new
    response = HTTP::Server::Response.new(io)
    headers = HTTP::Headers { "content" => "application/json" }
    body = hash.to_json
    request = HTTP::Request.new("POST", "/queues", headers, body)
    context = HTTP::Server::Context.new(request, response)
    return context
end

describe Scheduler::Enqueue do

    describe "default enqueue respon" do
        describe "has token" do
            it "return job_id > 0, when succeed process, with default queue" do
                context = createPostContext({ :test => "1234" })

                resources = Scheduler::Resources.new
                resources.qos(2, 2)
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)
                job_id, error_code = Scheduler::Enqueue.respon(context, resources)
    
                (job_id).should_not eq("0")

                # and the job shold be in lowest priority queue
                raw_redis = Redis.new("localhost", 6379)
                job_index = raw_redis.zrank("sorted_job_list_1", job_id)
                (job_index).should_not be_nil
            end
    
            it "return job_id > 0, when succeed process, with first queue" do
                context = createPostContext({ :test => "1234", :queue => "first" })

                resources = Scheduler::Resources.new
                resources.qos(2, 2)
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)
                job_id, error_code = Scheduler::Enqueue.respon(context, resources)
    
                (job_id).should_not eq("0")

                # and the job shold be in the first queue
                raw_redis = Redis.new("localhost", 6379)
                job_index = raw_redis.zrank("sorted_job_list_0", job_id)
                (job_index).should_not be_nil
            end
    
            it "return job_id > 0, when succeed process, with second queue" do
                context = createPostContext({ :test => "1234", :queue => "second" })

                resources = Scheduler::Resources.new
                resources.qos(3, 10)
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)
                job_id, error_code = Scheduler::Enqueue.respon(context, resources)
    
                (job_id).should_not eq("0")

                # and the job shold be in the second queue
                raw_redis = Redis.new("localhost", 6379)
                job_index = raw_redis.zrank("sorted_job_list_1", job_id)
                (job_index).should_not be_nil
            end

            it "return error_code = 1, when failed connect to redis server" do
                context = createPostContext({ :test => "1234", :queue => "first" })

                resources = Scheduler::Resources.new
                resources.qos(1, 11)
                resources.redis_client("localhost", 6380)
                resources.es_client("localhost", 9200)
                job_id, error_code = Scheduler::Enqueue.respon(context, resources)
    
                (job_id).should eq("0")
                error_code.should eq(1)
            end
        end

        describe "has no token" do
            it "return error_code = 2, when failed because of no token" do
                context = createPostContext({ :test => "1234"})

                resources = Scheduler::Resources.new
                resources.qos(1, 0)
                resources.redis_client("localhost", 6379)
                resources.es_client("localhost", 9200)
                job_id, error_code = Scheduler::Enqueue.respon(context, resources)
    
                (job_id).should eq("0")
                error_code.should eq(2)
            end
        end
    end

    describe "assign testbox | testgroup enqueue respon" do
        it "job has property testbox, but no test-group, save to testgroup_testbox queue" do
            context = createPostContext({ :test => "1234", :testbox => "myhost"})

            resources = Scheduler::Resources.new
            resources.qos(1, 0)
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9200)
    
            # here test for testbox == testgroup
            raw_redis = Redis.new("localhost", 6379)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "testgroup_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
    
            job_id, error_code = Scheduler::Enqueue.respon(context, resources)
            job_list = "testgroup_myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_id).should eq(job_info[0])

            job_list = "testbox_myhost"
            job_info = raw_redis.zrange(job_list, 0, -1, true)
            (job_info.size).should eq(0)
        end

        it "job has property testbox and test-group, save to testgroup_xxx queue not to testbox_xxx" do
            context = createPostContext({ :test => "1234", :testbox => "mygroup-1", "test-group" => "mygroup"})

            resources = Scheduler::Resources.new
            resources.qos(1, 0)
            resources.redis_client("localhost", 6379)
            resources.es_client("localhost", 9200)
    
            raw_redis = Redis.new("localhost", 6379)
            job_list = "testgroup_mygroup"
            raw_redis.zremrangebyrank(job_list, 0, -1)
            job_list = "testbox_myhost"
            raw_redis.zremrangebyrank(job_list, 0, -1)
    
            job_id, error_code = Scheduler::Enqueue.respon(context, resources)
            job_list = "testbox_myhost"
            job_info_b = raw_redis.zrange(job_list, 0, -1, true)
            job_list = "testgroup_mygroup"
            job_info_g = raw_redis.zrange(job_list, 0, -1, true)

            (job_id).should eq(job_info_g[0])
            (job_info_b.size).should eq 0
        end
    end
end
