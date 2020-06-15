require "./resources"
require "../redis_client"
require "../tools"

# requirement: find any job at peding queue, and return the job_id to caller
# - pending job at queue <sched/jobs_to_run/$tbox_group>
# - running job at queue <sched/jobs_running>
# -- and job info hash at queue <sched/id2job>
#
# inner process:
# 1.use redis client to find any job <job_id> and return the job_id
# 2.move <job_id> from <sched/jobs_to_run/tbox_group> to <sched/jobs_running>
# 3.update <sched/id2job>

module Scheduler::Dequeue
  def self.respon_testbox(testbox : String, env : HTTP::Server::Context, resources : Scheduler::Resources, count = 1)
    if resources.@redis_client != nil
      redis = resources.@redis_client.not_nil!
      es = resources.@es_client.not_nil!
      tbox_group = Public.get_tbox_group_name(testbox)
      count.times do
        job_id, queue_name = redis.find_any_job(tbox_group)

        if job_id != "0"
          redis.move_job(queue_name, "sched/jobs_running", "#{job_id}")
          job_content = es.get_job_content(job_id.to_s)
          case job_content
          when JSON::Any
            job_content = job_content.not_nil!.as_h.merge({"id" => job_id.to_s, "testbox" => "#{testbox}"})
            redis.add_job_content(job_content)
          else
            raise "Invalid job (id=#{job_id}) in es"
          end
          return "#{job_id}", queue_name
        end

        sleep(1)
      end
    end
    return "0", "0"
  end
end
