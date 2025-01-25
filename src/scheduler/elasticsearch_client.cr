# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "uri"
require "yaml"
require "json"
require "any_merge"
require "elasticsearch-crystal/elasticsearch/api"
require "elasticsearch-crystal/elasticsearch/api/utils"
require "./constants"
require "../lib/job"
require "../lib/json_logger"

# -------------------------------------------------------------------------------------------
# set_job(job_content)
#  - set job_content to es jobs/_doc/id["_source"]
#  - return response as JSON::Any
#
# get_job_content(id : String)
#  - get job_content from es jobs/_doc/id["_source"]
#  - return response as JSON::Any
#
# add(documents_path : String, content : Hash, id : String)
#  - add|replace hash content to es document
#  - documents_path index/document (default: JOB_INDEX_TYPE)
#
# update(documents_path : String, content : Hash)
#  - update hash content to es document
#
# -------------------------------------------------------------------------------------------
class Elasticsearch::Client

  @host : String
  @port : Int32

  def initialize
    initialize(Sched.options.es_host, Sched.options.es_port)
  end

  def initialize(host : String, port : Int32)
    user = Sched.options.es_user
    password = Sched.options.es_password
    host = "#{user}:#{URI.encode_www_form(password)}@#{host}" unless user.empty?() && password.empty?()

    @host = host
    @port = port
    settings = {
      :host => host,
      :port => port
    }
    if Sched.options.has_manticore
      settings[:manticore_host] = Sched.options.manticore_host
      settings[:manticore_port] = Sched.options.manticore_port
    end

    @client = Elasticsearch::API::Client.new(settings)
    @log = JSONLogger.new
  end

  def set_content_by_id(index, id, content)
    if @client.exists({ :index => index, :type => "_doc", :id => id })
      return @client.update(
        {
          :index => index, :type => "_doc",
          :refresh => "wait_for",
          :id => id,
          :body => { :doc => content },
        }
      )
    else
      return @client.create(
        {
          :index => index, :type => "_doc",
          :refresh => "wait_for",
          :id => id,
          :body => { :doc => content },
        }
      )
    end
  end

  # caller should judge response["_id"] != nil
  def set_job(job : Job, is_create = false)
    # time indicates the update time of each job event
    job.set_time

    if is_create
      response = create_job(job.to_json_any, job.id)
    else
      response = update_job(job.to_json_any, job.id)
    end

    @log.info("set job content, account: #{job.my_account}")

    return response
  end

  def get_job_content(job_id : String)
    response = @client.get_source({:index => "jobs", :type => "_doc", :id => job_id})
    case response
    when JSON::Any
      return response
    else
      return nil
    end
  end

  def get_job(job_id : String)
    response = get_job_content(job_id)

    case response
    when JSON::Any
      job = Job.new(response.as_h, job_id)
    else
      job = nil
    end

    return job
  end

  def get_account(my_email : String)
    query = {:index => "accounts", :type => "_doc", :id => my_email}
    response = JSON.parse({"_id" => my_email, "found" => false}.to_json)
    return response unless @client.exists(query)

    result = @client.get_source(query)
    raise result unless result.is_a?(JSON::Any)
    result
  end

  def get_hit_total(index, query)
    results = @client.search({:index => index, :body => query})
    raise results unless results.is_a?(JSON::Any)

    total = results["hits"]["total"]["value"].to_s.to_i32
    id = total >= 1 ? results["hits"]["hits"][0]["_source"]["id"] : 0

    return total, id
  end

  def search(index, query, ignore_error = true)
    results = @client.search({:index => index, :body => query})
    raise results unless results.is_a?(JSON::Any)

    return results["hits"]["hits"].as_a unless results.as_h.has_key?("error")

    error_results = Array(JSON::Any).new
    if ignore_error
      puts results
    else
      error_results << results
    end
    return error_results
  end

  def search_by_fields(index, query, size=10, source=Array(String).new, ignore_error = true)
      must = Array(Hash(String, Hash(String, Hash(String, String)))).new
      query.each do |field, value|
        must << {"term" => {field.to_s => {"value" => value.to_s}}}
      end
      real_query = {
        "_source" => source,
        "size" => size,
        "query" => {
          "bool" => {
            "must" => must
          }
        }
      }
      search(index, real_query, ignore_error)
  end

  def update_account(account_content : JSON::Any, my_email : String)
    return @client.update(
      {
        :index => "accounts", :type => "_doc",
        :id => my_email,
        :body => {:doc => account_content}
      }
    )
  end

  def get_tbox(testbox)
    query = {:index => "testbox", :type => "_doc", :id => testbox}
    return nil unless @client.exists(query)

    response = @client.get_source(query)
    case response
    when JSON::Any
      return response
    else
      return nil
    end
  end

  def update_tbox(testbox : String, wtmp_hash : Hash)
    query = {:index => "testbox", :type => "_doc", :id => testbox}
    if @client.exists(query)
      result = @client.get_source(query)
      raise result unless result.is_a?(JSON::Any)

      result = result.as_h
    else
      result = wtmp_hash
    end

    history = JSON::Any.new([] of JSON::Any)
    body = { "history" => history}

    body.any_merge!(result)
    body.any_merge!(wtmp_hash)

    @client.create(
      {
        :index => "testbox",
        :type => "_doc",
        :id => testbox,
        :body => body
      }
    )
  end

  def create_subqueue(content, id)
    return @client.create(
      {
        :index => "subqueue",
        :type => "_doc",
        :id => id,
        :body => content
      }
    )
  end

  private def create_job(job_content : JSON::Any, job_id : String)
    return @client.create(
      {
        :index => "jobs", :type => "_doc",
        :refresh => "wait_for",
        :id => job_id,
        :body => job_content,
      }
    )
  end

  private def update_job(job_content : JSON::Any, job_id : String)
    return @client.update(
      {
        :index => "jobs", :type => "_doc",
        :refresh => "wait_for",
        :id => job_id,
        :body => {:doc => job_content},
      }
    )
  end

  def delete(index, id)
    return @client.delete(
      {
        :index => index,
        :type => "_doc",
        :id => id
      }
    )
  end

  # [no use now] add a yaml file to es documents_path
  def add(documents_path : String, fullpath_file : String, id : String)
    yaml = YAML.parse(File.read(fullpath_file))
    return add(documents_path, yaml, id)
  end

  def perform_bulk_request(endpoint, path, body)
    headers = HTTP::Headers{ "Content-Type" => "application/x-ndjson"}
    response = HTTP::Client.post(endpoint, body: body, headers: headers)
    result = response.as(HTTP::Client::Response)
    JSON.parse(result.body)
  end

  def bulk(body, index="", type="_doc")
    method = "POST"
    body = bulkify(body)
    path = Elasticsearch::API::Utils.__pathify Elasticsearch::API::Utils.__escape(index), Elasticsearch::API::Utils.__escape(type), "_bulk"

    if Sched.options.has_manticore
      endpoint = "http://#{Sched.options.manticore_host}:#{Sched.options.manticore_port}/#{path}"
      perform_bulk_request(endpoint, path, body)
    end

    if Sched.options.has_es
      endpoint = "http://#{@host}:#{@port}/#{path}"
      perform_bulk_request(endpoint, path, body)
    end
  end

  # Convert an array of body into Elasticsearch format
  # Input: [
  # { :update => { :index => "1", :_type => "mytype", :_id => "1", :data => { :title => "update"}}},
  # { :create => { :index => "2", :_type => "mytype", :_id => "2", :data => { :title => "create"}}}
  # ]
  #
  # Output:
  # {"update":{"_index":"1","_type":"mytype","_id":"1"}}
  # { "doc": {"title":"update"}}
  # {"create":{"_index":"2","_type":"mytype","_id":"2"}}
  # {"title":"create"}
  #
  def bulkify(body)
    return body unless body.is_a?(Array)

    tmp = Array(String).new
    body.each do |item|
      unless item.is_a?(Hash)
        tmp << item
        next
      end
      data = item.values[0].delete("data")
      tmp << item.to_json
      next unless data

      if item.has_key?("update")
        tmp << {"doc" => data}.to_json
      else
        tmp << data.to_json
      end
    end
    tmp << ""
    tmp.join("\n")
  end
end

class Elasticsearch::API::Common::Client
  # copy and modify /c/compass-ci/lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr
  def perform_request(method, path, params={} of String => String, body={} of String => String | Nil)

    # normalize params to string
    new_params = {} of String => String
    params.each do |k,v|
      if !!v == v
        new_params[k.to_s] = ""
      else
        new_params[k.to_s] = v.to_s
      end
    end

    final_params = HTTP::Params.encode(new_params)

    if !body.nil?
      post_data = body.to_json
    else
      post_data = nil
    end

    if @settings.has_key? :manticore_host
      host_port = "#{@settings[:manticore_host]}:#{@settings[:manticore_port]}"
      response = perform_one(host_port, path, final_params, method, post_data)
    end

    host_port = "#{@settings[:host]}:#{@settings[:port]}"
    response = perform_one(host_port, path, final_params, method, post_data)

    result = response.as(HTTP::Client::Response)

    if result.headers["Content-Type"].includes?("application/json") && method != "HEAD"
      final_response = JsonResponse.new result.status_code, JSON.parse(result.body), result.headers
    else
      final_response = Response.new result.status_code, result.body.as(String), result.headers
    end

    final_response

  end

  def perform_one(host_port, path, final_params, method, post_data)
    if method == "GET"
      endpoint = "http://#{host_port}/#{path}?#{final_params}"
      response = HTTP::Client.get(endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
    elsif method == "POST"
      endpoint = "http://#{host_port}/#{path}"
      response = HTTP::Client.post(url: endpoint, body: post_data)
    elsif method == "PUT"
      endpoint = "http://#{host_port}/#{path}"
      response = HTTP::Client.put(url: endpoint, body: post_data)
    elsif method == "DELETE"
      endpoint = "http://#{host_port}/#{path}?#{final_params}"
      response = HTTP::Client.delete(url: endpoint)
    elsif method == "HEAD"
      endpoint = "http://#{host_port}/#{path}"
      response = HTTP::Client.head(url: endpoint)
    end
    return response
  end

end
