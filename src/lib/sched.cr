require "./job"
require "../scheduler/redis_client"
require "../scheduler/elasticsearch_client"

class Sched

    property es
    property redis

    def initialize()
        @es = Elasticsearch::Client.new
        @redis = Redis::Client.new
    end

    def set_host_mac(mac : String, hostname : String)
        @redis.set_hash_queue("sched/mac2host", mac, hostname)
    end

    private def save_job_data(job : Job)
        @es.set_job_content(job)
        @redis.add2queue("sched/jobs_to_run/" + job.tbox_group, job.id)

        return job.id, 0
    end

    def submit_job(env : HTTP::Server::Context)
        body = env.request.body.not_nil!.gets_to_end
        job_content = JSON.parse(body)

        # use redis incr as sched/seqno2jobid
        job_id = @redis.get_new_job_id()
        if job_id == "0"
            return job_id, 1
        end

        job_content["id"] = job_id
        job = Job.new(job_content)

        return save_job_data(job)
    end

    def close_job(job_id : String)
        job = @redis.get_job(job_id)

        respon = @es.set_job_content(job)
        if respon["_id"] == nil
            # es update fail, raise exception
            raise "es set job content fail! "
        end

        @redis.remove_finished_job(job_id)
    end
end
