require "elasticsearch-crystal/elasticsearch/api"
require "../constants.cr"

class RegressionClient
  HOST = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
  PORT = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

  def initialize(host = HOST, port = PORT, auth = true)
    if auth
      user = ENV["ES_USER"]?
      password = ENV["ES_PASSWORD"]?
      host = "#{user}:#{URI.encode_www_form(password)}@#{host}" if user && password
    end

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
    total = result["hits"]["total"]["value"]
    if total.is_a?(JSON::Any)
      total = total.as_i
    else
      raise "query result type error."
    end
    return total > 0
  end
end
