require "spec"
require "file_utils"
require "../src/configure"

describe Configure do
    describe "default initialize" do
        it "default initialize" do
            config = Configure::YamlFileOperate.new

            config.redisHost.should  eq("localhost")
            config.redisPort.should  eq(6379)

            config.elasticSearchHost.should  eq("localhost")
            config.elasticSearchPort.should  eq(9200)
        end
    end

    describe "configure file initialize" do
        it "initialize file is matched" do
            configureFileName = "test_config.yaml"
            File.open(configureFileName, "w") do |f|
                data = YAML.parse <<-END
                ---
                redis:
                    host: localhost_1
                    port: 3020
                elasticsearch:
                    host: localhost_4
                    port: 9100
                END
                YAML.dump(data, f)
            end
            config = Configure::YamlFileOperate.new(configureFileName)
            
            config.redisHost.should  eq("localhost_1")
            config.redisPort.should  eq(3020)

            config.elasticSearchHost.should  eq("localhost_4")
            config.elasticSearchPort.should  eq(9100)

            FileUtils.rm(configureFileName)
        end

        it "initialize file content nomatched" do
            configureFileName = "test_config.yaml"
            File.open(configureFileName, "w") do |f|
                data = YAML.parse <<-END
                ---
                redis:
                    host1: localhost_1
                    port: 3010
                elasticsearch:
                    host: localhost_4
                    port: 9200
                END
                YAML.dump(data, f)
            end
            config = Configure::YamlFileOperate.new(configureFileName)
            
            config.redisHost.should  eq("localhost")
            config.redisPort.should  eq(6379)

            FileUtils.rm(configureFileName)
        end

        it "initialize file not exists" do
            configureFileName = "not_exists_file.yaml"
            config = Configure::YamlFileOperate.new(configureFileName)
            config.redisHost.should  eq("localhost")
            config.redisPort.should  eq(6379)
   
            config.elasticSearchHost.should  eq("localhost")
            config.elasticSearchPort.should  eq(9200)
     end
    end
end