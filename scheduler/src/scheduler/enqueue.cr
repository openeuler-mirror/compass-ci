require "json"

require  "./resources"

require "../tools"
require "../redis_client"
require "../elasticsearch_client"

# --------------------------------------------------------------------------------
# 1.save user <job> (json data) to <Elasticsearch> document
#  - generate a sequence <job_id> from redis key ("sched/seqno2jobid") incr
#  - Elasticsearch save job to <jobs/job> (index/document)
#  - Elasticsearch use <job_id> as document <id>
#
# --------------------------------------------------------------------------------
# 2.respon <job_id> that index to the user job
#  - if (job_id == 0) means failed to add job to queue
#    -- caused by <failed connect to redis> : errcode = 1
#    -- caused by <failed connect to es> : errcode = 3
#
# --------------------------------------------------------------------------------
# 3.user can special which queue to add to
#  - when assigned testbox | test-group, push to special queue
#   -- queue name map to redis sorted set keyname
#    --- :waitting => "waitting" {no used yet}
#    --- :running => "running"  {scheduler use : when pull to running}
#    --- :pending[n] => "testgroup_[testgroup_name]"
#    --- testgroup_name = testbox_name[-n]

module Scheduler::Enqueue

    # testbox is a instance of test-group
    def self.determinQueueName(hash : Hash)
        queue_name = ""
        queue_name_json = hash["test-group"]?
        if hash["test-group"]?
            queue_name = hash["test-group"].not_nil!.to_s
        elsif hash["testbox"]?
            testbox_name = hash["testbox"].not_nil!.to_s
            queue_name = Public.getTestgroupName(testbox_name)
        end

        return queue_name.to_s
    end

    def self.saveData(queue_name : String, hash : Hash, resources : Scheduler::Resources)
        error_code = 0

        # use redis incr as sched/seqno2jobid
        job_id = resources.@redis_client.not_nil!.get_new_job_id()

        if (job_id != "0")
            resources.@es_client.not_nil!.add("/jobs/job", hash, job_id)
            resources.@redis_client.not_nil!.add2queue(queue_name, job_id)
        else
            error_code = 1  # failed to connect to redis server (queue)
        end
        return job_id, error_code
    end

    def self.respon(env : HTTP::Server::Context, resources : Scheduler::Resources)
        job_id ="0"
        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)
        job_hash = job_content.as_h

        queue_name = determinQueueName(job_hash)
        job_hash = Public.hashReplaceWith(job_hash, { "test-group" =>  queue_name })

        return saveData("testgroup_" + queue_name, job_hash, resources)
    end
end
