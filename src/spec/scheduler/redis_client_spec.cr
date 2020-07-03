require "spec"
require "scheduler/redis_client"
require "scheduler/constants"

describe Redis::Client do
  describe "enqueue" do
    it "enqueue success" do
      redis_client = Redis::Client.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
      id = redis_client.get_new_job_id

      before_add_priority = Time.local.to_unix_f
      redis_client.add2queue("test", id)

      raw_redis = Redis.new(JOB_REDIS_HOST, JOB_REDIS_PORT_DEBUG)
      index = raw_redis.zrank("test", id)

      index.should_not be_nil

      # job priority is more later
      respon = raw_redis.zrange("test", index, index, true)
      respon[1].to_s.to_f64.should be_close(before_add_priority, 0.1)
    end
  end
end
