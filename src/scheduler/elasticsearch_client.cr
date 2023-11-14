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

# -------------------------------------------------------------------------------------------
# set_job_content(job_content)
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
  class_property :client
  HOST = (ENV.has_key?("ES_HOST") ? ENV["ES_HOST"] : JOB_ES_HOST)
  PORT = (ENV.has_key?("ES_PORT") ? ENV["ES_PORT"] : JOB_ES_PORT).to_i32

  def initialize(host = HOST, port = PORT, auth = true)
    if auth
      user = ENV["ES_USER"]?
      password = ENV["ES_PASSWORD"]?
      host = "#{user}:#{URI.encode_www_form(password)}@#{host}" if user && password
    end
    @host = host.as(String)
    @port = port.to_s.as(String)
    @client = Elasticsearch::API::Client.new({:host => host, :port => port})
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
  def set_job_content(job : Job, is_create = false)
    # time indicates the update time of each job event
    job.set_time

    if is_create
      response = create(job.to_json_any, job.id)
    else
      response = update(job.to_json_any, job.id)
    end

    return response
  end

  def update_job(job : Job)
    job.set_time
    update(job.to_json_any, job.id)
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

  private def create(job_content : JSON::Any, job_id : String)
    return @client.create(
      {
        :index => "jobs", :type => "_doc",
        :refresh => "wait_for",
        :id => job_id,
        :body => job_content,
      }
    )
  end

  private def update(job_content : JSON::Any, job_id : String)
    return @client.update(
      {
        :index => "jobs", :type => "_doc",
        :refresh => "wait_for",
        :id => job_id,
        :body => {:doc => job_content},
      }
    )
  end

  # [no use now] add a yaml file to es documents_path
  def add(documents_path : String, fullpath_file : String, id : String)
    yaml = YAML.parse(File.read(fullpath_file))
    return add(documents_path, yaml, id)
  end

  def perform_bulk_request(path, body)
    endpoint = "http://#{@host}:#{@port}/#{path}"
    headers = HTTP::Headers{ "Content-Type" => "application/x-ndjson"}
    response = HTTP::Client.post(endpoint, body: body, headers: headers)
    result = response.as(HTTP::Client::Response)
    JSON.parse(result.body)
  end

  def bulk(body, index="", type="_doc")
    method = "POST"
    body = bulkify(body)
    path = Elasticsearch::API::Utils.__pathify Elasticsearch::API::Utils.__escape(index), Elasticsearch::API::Utils.__escape(type), "_bulk"
    perform_bulk_request(path, body)
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
