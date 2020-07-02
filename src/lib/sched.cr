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
end
