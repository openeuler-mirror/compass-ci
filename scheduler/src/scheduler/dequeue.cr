require "./resources"
require "../redis_client"
require "../tools"

# requirement: find any job at peding queue, and return the job_id to caller
# - pending job at queue <testgroup_xxx>
# - running job at queue <running>
# -- and help infomation abount running job at queue <hi_running>
#
# inner process:
# 1.use redis client to find any job <job_id> and return the job_id
# 2.move <job_id> from <testgroup_xxx> to <running> and update <hi_running> 

module Scheduler::Dequeue
  def self.responTestbox(testbox : String, env : HTTP::Server::Context, resources : Scheduler::Resources, count = 1)
    if resources.@redis_client != nil
      client = resources.@redis_client.not_nil!
      testgroup = Public.getTestgroupName(testbox)
      count.times do
        job_id, queue_name = client.findAnyJob(testgroup)

        if job_id != "0"
          client.moveJob(queue_name, "running", "#{job_id}", testbox)
          return "#{job_id}", queue_name
        end

        sleep(1)
      end
    end
    return "0", "0"
  end
end
