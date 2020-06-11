require "spec"
require "scheduler/elasticsearch_client"
require "scheduler/constants"

describe  Elasticsearch::Client do
    describe "add job" do
        it "add job without job id success" do
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "testjobs"})

            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            es_client.add("/test#{JOB_INDEX_TYPE}", {"foo" => "bar", "result_root" => "iperf"}, "1")

            # when not find
            # { "error" => {"root_cause" => [{"type" => "index_not_found_exception",..."index" => "testjobs"}],
            #                          "type" => "index_not_found_exception",..."index" => "testjobs"},
            #   "status" => 404}
            # when find
            # {"_index" => "testjobs", "_type" => "job", "_id" => "1", ..."found" => true, "_source" => {"foo" => "bar"}}
            respon =  raw_es_client.get({:index => "testjobs", :id => "1"})
            (respon["_id"]).should_not  be_nil
            (respon["_source"]["id"]?).should_not  be_nil
            (respon["_source"]["id"].to_s).should eq("1")

            raw_es_client.indices.delete({:index => "testjobs"})
        end

        it "add job with job id success" do
            es_client = Elasticsearch::Client.new(JOB_ES_HOST, JOB_ES_PORT_DEBUG)
            raw_es_client = Elasticsearch::API::Client.new( { :host => JOB_ES_HOST, :port => JOB_ES_PORT_DEBUG } )
            raw_es_client.indices.delete({:index => "testjobs"})
            es_client.add("/test#{JOB_INDEX_TYPE}", {"foo" => "bar", "id" => "3", "result_root" => nil}, "2")

            respon =  raw_es_client.get({:index => "testjobs", :id => "2"})
            (respon["_id"]).should_not  be_nil
            (respon["_source"]["id"]?).should_not  be_nil
            (respon["_source"]["id"].to_s).should eq("2")

            raw_es_client.indices.delete({:index => "testjobs"})
        end
    end
end
