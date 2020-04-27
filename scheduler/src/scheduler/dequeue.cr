require  "./qos"
require  "./resources"
require "../redis_client"
require "../elasticsearch_client"

require "../tools"

# 1.find any job <job_id>...
# 2.move <job_id> from <pending-queue>  to <running-queue>

module Scheduler::Dequeue

    # find any job in queues
    def self.findAnyJob(client : Redis::Client, qos : Scheduler::Qos)
        job_id = "0"
        queue_name = "sorted_job_list_0"

        qos.@queueNum.times do |index|
            job_id, queue_name = client.findAnyJob(qos.@previousGetJobQueueID)
            qos.switchtoNextQueue()

            # job find ? break
            break unless job_id == "0"
        end

        return job_id, queue_name
    end

    def self.respon(env : HTTP::Server::Context, resources : Scheduler::Resources, count = 1)
        if (resources.@redis_client == nil) || (resources.@qos == nil) 
            return "0", "0"
        end

        client = resources.@redis_client.not_nil!
        qos = resources.@qos.not_nil!
        count.times do
            job_id, queue_name = findAnyJob(client, qos)

            # remove job to running queue
            if job_id != "0"
                client.moveJob(queue_name, "running", "#{job_id}")
                return "#{job_id}", queue_name
            end

            sleep(1)
        end

        return "0", "0"
    end

    # ---------------------------
    def self.responTestbox(testbox : String, env : HTTP::Server::Context, resources : Scheduler::Resources, count = 1)
        if resources.@redis_client == nil
            return "0", "0"
        end

        testgroup = Public.getTestgroupName(testbox)
        client = resources.@redis_client.not_nil!
        count.times do
            job_id, queue_name = client.findAnyJob(testgroup)
            # pending job is in testgroup_xxx queue
            # move running job to testbox_xxx

            # remove job to running queue
            # update job's testbox property
            if job_id != "0"
                client.moveJob(queue_name, "running", "#{job_id}", testbox)
                return "#{job_id}", queue_name
            end

            sleep(1)
        end

        return "0", "0"
    end
end