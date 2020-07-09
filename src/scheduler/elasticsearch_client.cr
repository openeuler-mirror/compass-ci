require "yaml"
require "json"
require "elasticsearch-crystal/elasticsearch/api"
require "./tools"
require "./constants"
require "../lib/job"

# -------------------------------------------------------------------------------------------
# set_job_content(job_content)
#  - set job_content to es jobs/_doc/id["_source"]
#  - return response as JSON::Any
#
# get_job_content(id : String)
#  - get job_content from es jobs/_doc/id["_source"]
#  - return response as JSON::Any
#
# -------------------------------------------------------------------------------------------
# below function will be Deprecated
#
# add(documents_path : String, content : Hash, id : String)
#  - add|replace hash content to es document
#  - documents_path index/document (default: JOB_INDEX_TYPE)
#
# get(documents_path : String, id : String)
#  - get content from es documents_path/id
#
# update(documents_path : String, content : Hash)
#  - update hash content to es document
#
# -------------------------------------------------------------------------------------------
class Elasticsearch::Client
    class_property :client
    HOST = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
    PORT = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

    def initialize(host = HOST, port = PORT)
        @client = Elasticsearch::API::Client.new( { :host => host, :port => port } )
    end

    # caller should judge response["_id"] != nil
    def set_job_content(job_content : JSON::Any)
        if job_content["id"]?
            job_id = job_content["id"].to_s
            response = get_job_content(job_id)
            if response["id"]?
                response = update(job_content, job_id)
            else
                response = create(job_content, job_id)
            end
        else
            response = {"_id" => nil, "job_content" => job_content}
        end

        return response
    end

    # caller should judge response["_id"] != nil
    def set_job_content(job : Job)
        response = get_job_content(job.id)
        if response["id"]?
            response = update(job.dump_to_json_any, job.id)
        else
            response = create(job.dump_to_json_any, job.id)
        end

        return response
    end

    # caller should judge response["id"]?
    def get_job_content(job_id : String)
        if @client.exists({:index => "jobs", :type => "_doc", :id => job_id})
            response = @client.get_source({:index => "jobs", :type => "_doc", :id => job_id})
        else
            response = {"_id" => job_id, "found" => false}
        end

        return response
    end

    private def create(job_content : JSON::Any, job_id : String)
        return @client.create(
            {
                :index => "jobs", :type => "_doc",
                :id => job_id,
                :body => job_content
            }
        )
    end

    private def update(job_content : JSON::Any, job_id : String)
        return @client.update(
            {
                :index => "jobs", :type => "_doc",
                :id => job_id,
                :body => { :doc => job_content }
            }
        )
    end

    @[Deprecated("Use `#get_job_content` instead")]
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

    @[Deprecated("Use `#set_job_content` instead")]
    def add(documents_path : String, content : Hash, id : String)
        if content["suite"]?
            result_root = "/result/#{content["suite"]}/#{id}"
        else
            result_root = "/result/default/#{id}"
        end
        content = content.merge({"result_root" => result_root, "id" => id})

        dp = documents_path.split("/")
        response = @client.create(
            {
                :index => dp[dp.size - 2],
                :type => dp[dp.size - 1],
                :id => id,
                :body => content
            }
        )
        return response
    end

    @[Deprecated("Use `#set_job_content` instead")]
    def update(documents_path : String, content : Hash)
        dp = documents_path.split("/")
        id = content["id"].to_s
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

    # [no use now] add a yaml file to es documents_path
    def add(documents_path : String, fullpath_file : String, id : String)
        yaml = YAML.parse(File.read(fullpath_file))
        return add(documents_path, yaml, id)
    end
end
