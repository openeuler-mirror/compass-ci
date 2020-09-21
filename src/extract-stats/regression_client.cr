require "elasticsearch-crystal/elasticsearch/api"
require "../scheduler/constants.cr"

class RegressionClient
  HOST = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
  PORT = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

  def initialize(host = HOST, port = PORT)
    @client = Elasticsearch::API::Client.new({:host => host, :port => port})
  end

  def store_error_info(error_id : String, job_id : String)
    @client.create({
      :index => "regression",
      :type  => "_doc",
      :body  => {
        "error_id" => error_id,
        "job_id"   => job_id,
      },
    })
  end

  def check_error_id(error_id : String)
    query_body = {
      "query" => {
        "term" => {
          "error_id" => error_id,
        },
      },
    }
    result = @client.search({
      :index => "regression",
      :type  => "_doc",
      :body  => query_body,
    })
    raise "query failed." unless result["hits"]? || result["hits"]["total"]?
    total = result["hits"]["total"]
    if total.is_a?(JSON::Any)
      total = total.as_i
    else
      raise "query result type error."
    end
    return total > 0
  end
end
