require "yaml"
require "json"
require "elasticsearch-crystal/elasticsearch/api"
require "./tools"

# -------------------------------------------------------------------------------------------
# add(documents_path : String, content : Hash, id : String)
#  - add|replace hash content to es document
#  - documents_path index/document( default: jobs/job | /jobs/job]
# get(documents_path : String, id : String)
#  - get content from es documents_path/id
#
# -------------------------------------------------------------------------------------------
# update(documents_path : String, content : Hash, id : String)
#  - update hash content to es document
#
# -------------------------------------------------------------------------------------------
# add_config(documents_path : String, hash : Hash)
#  - add|replace a <mac> => <hostname>, use <mac> as document id
#  - add|replace a <ip:port> => <hostname>, use <ip:port> as document id

class Elasticsearch::Client
    class_property :client

    def initialize(hostname : String, port : Int32)
        @client = Elasticsearch::API::Client.new( { :host => hostname, :port => port } )
    end

    def get(documents_path : String, id : String)
        dp = documents_path.split("/")
        response = @client.get(
            {
                :index => dp[dp.size - 2],
                :type => dp[dp.size - 1],
                :id => id
            }
        )
        return response
    end
    
    def add(documents_path : String, content : Hash, id : String)
        content_hash = Public.hashReplaceWith(content, {"id" => id})
        result_root = "/result"
        if content["result_root"]?
            result_root = content["result_root"]
        elsif content["testcase"]?
            testcase = content["testcase"]
            result_root = "#{result_root}/#{testcase}"            
        end
        content_hash = Public.hashReplaceWith(content_hash, {"result_root" => "#{result_root}/#{id}"})

        dp = documents_path.split("/")
        response = @client.create(
            {
                :index => dp[dp.size - 2],
                :type => dp[dp.size - 1],
                :id => id,
                :body => content_hash
            }
        )
        return response
    end

    def update(documents_path : String, content : Hash, id : String)
        dp = documents_path.split("/")
        response = @client.update(
            {
                :index => dp[dp.size - 2],
                :type => dp[dp.size - 1],
                :id => id,
                :body => { :doc => content }
            }
        )
        return response
    end

    # {"report":{"mappings":{"properties":{"hostname":{"type":"text","fields":{"keyword":{"type":"keyword","ignore_above":256}}}}}

    def get_config(documents_path : String, id : String)
        dp = documents_path.split("/")
        response = @client.get(
            {
                :index => dp[dp.size - 2],
                :type => dp[dp.size - 1],
                :id => id
            }
        )

        if (response["found"]?) && (response["found"] == true)
            return response["_source"]["hostname"].to_s
        else
            return nil
        end
    end

    # [no use now] add a yaml file to es documents_path
    def add(documents_path : String, fullpath_file : String, id : String)
        yaml = YAML.parse(File.read(fullpath_file))
        return add(documents_path, yaml, id)
    end
end
