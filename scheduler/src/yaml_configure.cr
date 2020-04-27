require "yaml"

module YamlConfigure
    class ServerConfig
        include YAML::Serializable

        property host : String
        property port : Int32
    end

    class SchedulerConfig
        include YAML::Serializable

        property redis : ServerConfig
        property elasticsearch : ServerConfig
    end
end