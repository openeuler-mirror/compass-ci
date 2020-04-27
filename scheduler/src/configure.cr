require "yaml"
require "./yaml_configure"

# 1.configure data saved in YAML file

module Configure
    class YamlFileOperate
        property redisHost : String
        property redisPort : Int32

        property elasticSearchHost : String
        property elasticSearchPort  : Int32 

        def read_config(configureFile : String)
            if !File.exists?(configureFile)
                return
            end

            begin
                cc = YamlConfigure::SchedulerConfig.from_yaml(File.open(configureFile, "r"))

                @redisHost = cc.redis.host
                @redisPort = cc.redis.port
    
                @elasticSearchHost = cc.elasticsearch.host
                @elasticSearchPort = cc.elasticsearch.port
            rescue exception
                # not matched config file, what to do?
            end
        end

        def initialize(configureFile = nil)
            @redisHost = "localhost"
            @redisPort = 6379

            @elasticSearchHost = @redisHost
            @elasticSearchPort = 9200

            read_config("#{configureFile}")
        end
    end
end
