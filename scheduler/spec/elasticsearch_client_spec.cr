require "spec"
require "../src/elasticsearch_client"

describe  Elasticsearch::Client do
    describe "add job" do
        it "add job without job id success" do
            raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
            raw_es_client.indices.delete({:index => "testjobs"})

            es_client = Elasticsearch::Client.new("localhost", 9200)
            respon = es_client.add("/testjobs/job", {"foo" => "bar", "result_root" => "iperf"}, "1")

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
            es_client = Elasticsearch::Client.new("localhost", 9200)
            raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
            raw_es_client.indices.delete({:index => "testjobs"})
            es_client.add("/testjobs/job", {"foo" => "bar", "id" => "3", "result_root" => nil}, "2")

            respon =  raw_es_client.get({:index => "testjobs", :id => "2"})
            (respon["_id"]).should_not  be_nil
            (respon["_source"]["id"]?).should_not  be_nil
            (respon["_source"]["id"].to_s).should eq("2")

            raw_es_client.indices.delete({:index => "testjobs"})
        end
    end

    describe "add config" do
        it "add config and get when there has mac infomation" do
            es_client = Elasticsearch::Client.new("localhost", 9200)
            raw_es_client = Elasticsearch::API::Client.new( { :host => "localhost", :port => 9200 } )
            raw_es_client.indices.delete({:index => "testjobs"})

            data = {:address => "192.168.0.1:1234", :hostname => "1234", :mac => "ef-01-02-03-04-05"}
            test_document = "/testjobs/hostnames"
            es_client.add_config(test_document, data)

            respon = es_client.get_config(test_document, "ef-01-02-03-04-05")
            respon.should eq("1234")

            raw_es_client.indices.delete({:index => "testjobs"})
        end
    end
end
