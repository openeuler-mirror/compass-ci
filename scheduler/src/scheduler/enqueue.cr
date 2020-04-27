require "json"

require  "./qos"
require  "./resources"

require "../tools"
require "../redis_client"
require "../elasticsearch_client"

# --------------------------------------------------------------------------------
# 1.save user <job> (json data) to <Elasticsearch> document
#  - generate a global <job_id> from redis key ("global_job_id") incr
#  - Elasticsearch save job to <jobs/job> (index/document)
#  - Elasticsearch use <job_id> as document <id>
#
# --------------------------------------------------------------------------------
# 2.respon <job_id> that index to the user job
#  - if (job_id == 0) means failed to add job to queue
#    -- caused by <no token> : errcode = 2
#    -- caused by <failed connect to redis> : errcode = 1
#    -- caused by <failed connect to es> : errcode = 3
#
# --------------------------------------------------------------------------------
# 3.user can special which queue to add to
#  - when assigned testbox | test-group, push to special queue
#   -- no qos control : rate control
#   -- queue name map to redis sorted set keyname
#    --- :running[n] => "testbox_running_[testbox_name]"  {scheduler use : when pull to running}
#    --- :pending[n] => "testgroup_[testgroup_name]"
#    --- testgroup_name = testbox_name[-n]
#
#  - when no assign testbox | test-group, push to global queue
#   -- the priority is controle by scheduler (qos : rate control)
#   -- if the use not specified queue name, then add to lowest priority queue
#   -- queue name map to redis sorted set keyname
#    --- :waitting => "waitting" {no used yet}
#    --- :running => "running" {scheduler use : when pull to running}
#    --- :pending[n] => "sorted_job_list_[n]"

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

    def self.determinQueueID(hash : Hash, qos : Scheduler::Qos)
        queue_name = ""
        queue_name_json = hash["queue"]?
        if queue_name_json != nil
            queue_name = queue_name_json.to_s
        end

        # first, second, ... => 0, 1, ... => redis sorted set keyname (sorted_job_list_[0,1,...])
        queue_id  = qos.queueNameTranslate(queue_name)
        return queue_id
    end

    def self.saveData(queue_name : String, hash : Hash, resources : Scheduler::Resources)
        error_code = 0

        # use redis incr as global job_id
        job_id = resources.@redis_client.not_nil!.getSN()

        if (job_id != "0")
            resources.@es_client.not_nil!.add("/jobs/job", hash, job_id)
            resources.@redis_client.not_nil!.add2queue(queue_name, job_id)
        else
            error_code = 1  # failed to connect to redis server (queue)
        end
        return job_id, error_code
    end

    def self.defaultRespon(hash : Hash, resources : Scheduler::Resources)
        job_id ="0"
        queue_id = determinQueueID(hash, resources.@qos.not_nil!)
        if resources.@qos.not_nil!.queueTokenNum(queue_id) == 0
            return job_id, 2  # no token
        end

        return saveData(resources.@redis_client.not_nil!.id2name(queue_id), hash, resources)
    end

    # queue_name : like testgroup_hostgroup
    def self.assignRespon(queue_name : String, hash : Hash, resources : Scheduler::Resources)
        return saveData(queue_name, hash, resources)
    end

    def self.respon(env : HTTP::Server::Context, resources : Scheduler::Resources)
        error_code = errconnectCode(resources)
        job_id ="0"
        if  error_code != 0
            return job_id, error_code
        end

        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)
        job_hash = job_content.as_h

        queue_name = determinQueueName(job_hash)
        case queue_name
        when ""
            return defaultRespon(job_hash, resources)
        else
            job_hash = Public.hashReplaceWith(job_hash, { "test-group" =>  queue_name })
            return assignRespon("testgroup_" + queue_name, job_hash, resources)
        end
    end

    def self.errconnectCode(resources : Scheduler::Resources)
        error_code = 0
        if (resources.@redis_client == nil) || (resources.@qos == nil) || (resources.@es_client == nil )
            if resources.@redis_client == nil
                error_code = 1
            end
            if resources.@qos == nil
                error_code = 2
            end
            if resources.@es_client == nil
                error_code = 3
            end
        end

        return error_code
    end
end
