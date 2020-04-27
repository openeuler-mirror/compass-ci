require "spec"
require "file_utils"
require "../src/yaml_configure"

describe YamlConfigure do
    describe "configure file initialize" do
        it "initialize as release model" do
            configureFileName = "test_config.yaml"
            File.open(configureFileName, "w") do |f|
                data = YAML.parse <<-END
                ---
                redis:
                    host: localhost_1
                    port: 3010
                elasticsearch:
                    host: localhost_4
                    port: 9200
                END
                YAML.dump(data, f)
            end

            cc = YamlConfigure::SchedulerConfig.from_yaml(File.open(configureFileName, "r"))
            cc.elasticsearch.host.should eq("localhost_4")
            cc.elasticsearch.port.should eq(9200)
            
            FileUtils.rm(configureFileName)
        end
    end
end