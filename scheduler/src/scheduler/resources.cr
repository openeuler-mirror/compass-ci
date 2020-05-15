require "../redis_client"
require "../elasticsearch_client"

module Scheduler
    class Resources

        class_property :redis_client, :es_client, :qos
        class_property :fsdir_root
        class_property :test_params

        def es_client(host : String, port : Int32)
            @es_client = Elasticsearch::Client.new(host, port)
        end

        def redis_client(host : String, port : Int32)
            @redis_client = Redis::Client.new(host, port)
        end

        def fsdir_root(dirname : String)
            @fsdir_root = dirname
        end

        def test_params(params : Array(String))
            @test_params = params
        end
    end
end
