require "spec"
require "scheduler/elasticsearch_client"
require "scheduler/constants"

describe  Elasticsearch::Client do
    describe "add job" do
        it "add job without job id success" do
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "jobs"})

            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            es_client.add(JOB_INDEX_TYPE, {"foo" => "bar", "result_root" => "iperf"}, "1")

            # when not find
            # { "error" => {"root_cause" => [{"type" => "index_not_found_exception",..."index" => "jobs"}],
            #                          "type" => "index_not_found_exception",..."index" => "jobs"},
            #   "status" => 404}
            # when find
            # {"_index" => "jobs", "_type" => "job", "_id" => "1", ..."found" => true, "_source" => {"foo" => "bar"}}
            respon =  raw_es_client.get({:index => "jobs", :id => "1"})
            (respon["_id"]).should_not  be_nil
            (respon["_source"]["id"]?).should_not  be_nil
            (respon["_source"]["id"].to_s).should eq("1")

            raw_es_client.indices.delete({:index => "jobs"})
        end

        it "add job with job id success" do
            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "jobs"})
            es_client.add(JOB_INDEX_TYPE, {"foo" => "bar", "id" => "3", "result_root" => nil}, "2")

            respon =  raw_es_client.get({:index => "jobs", :id => "2"})
            (respon["_id"]).should_not  be_nil
            (respon["_source"]["id"]?).should_not  be_nil
            (respon["_source"]["id"].to_s).should eq("2")

            raw_es_client.indices.delete({:index => "jobs"})
        end

        it "get job content with right job id" do
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "jobs"})

            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            test_json = JSON.parse({"foo" => "bar", "id" => "10", "result_root" => nil}.to_json)

            raw_es_client.create(
                {
                    :index => "jobs",
                    :type => "_doc",
                    :id => "10",
                    :body => test_json,
                }
            )

            respon = es_client.get_job_content("10")
            (respon).should_not  be_nil
            (respon.not_nil!["id"]?).should_not  be_nil
            (respon.not_nil!["id"].to_s).should eq("10")

            raw_es_client.indices.delete({:index => "jobs"})
        end

        it "get job content with wrong job id" do
            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "jobs"})

            respon = es_client.get_job_content("10")
            (respon.not_nil!["id"]?).should be_nil
        end
    end
end
