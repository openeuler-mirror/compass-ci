require "json"

require  "./resources"

require "../tools"
require "../redis_client"
require "../elasticsearch_client"

# --------------------------------------------------------------------------------
# 1.save user <job> (json data) to <Elasticsearch> document
#  - generate a sequence <job_id> from redis key ("sched/seqno2jobid") incr
#  - Elasticsearch save job to <JOB_INDEX_TYPE> (index/document)
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
#  - when assigned testbox | tbox_group, push to special queue
#   -- queue name map to redis sorted set keyname
#    --- :waitting => "waitting" {no used yet}
#    --- :running => "sched/jobs_running"  {scheduler use : when pull to running}
#    --- :pending[n] => "sched/jobs_to_run/$tbox_group"
#    --- tbox_group = ($tbox_group or ${testbox%-NUMBER}) in job.yaml

module Scheduler::Enqueue

    # testbox is a instance of tbox_group
    def self.determin_queue_name(hash : Hash)
        queue_name = ""
        if hash["tbox_group"]?
            queue_name = hash["tbox_group"].not_nil!.to_s
        elsif hash["testbox"]?
            testbox = hash["testbox"].not_nil!.to_s
            queue_name = Public.get_tbox_group_name(testbox)
        end

        return queue_name.to_s
    end

    def self.save_data(queue_name : String, hash : Hash, resources : Scheduler::Resources)
        error_code = 0

        # use redis incr as sched/seqno2jobid
        job_id = resources.@redis_client.not_nil!.get_new_job_id()

        if (job_id != "0")
            resources.@es_client.not_nil!.add(JOB_INDEX_TYPE, hash, job_id)
            resources.@redis_client.not_nil!.add2queue(queue_name, job_id)
        else
            error_code = 1  # failed to connect to redis server (queue)
        end
        return job_id, error_code
    end

    def self.respon(env : HTTP::Server::Context, resources : Scheduler::Resources)
        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)
        job_hash = job_content.as_h

        queue_name = determin_queue_name(job_hash)
        job_hash = Public.hash_replace_with(job_hash, { "tbox_group" =>  queue_name })

        return save_data("sched/jobs_to_run/" + queue_name, job_hash, resources)
    end
end
