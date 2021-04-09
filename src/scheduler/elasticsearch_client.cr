# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "yaml"
require "json"
require "any_merge"
require "elasticsearch-crystal/elasticsearch/api"
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

  def initialize(host = HOST, port = PORT)
    @client = Elasticsearch::API::Client.new({:host => host, :port => port})
  end

  # caller should judge response["_id"] != nil
  def set_job_content(job : Job)
    # time indicates the update time of each job event
    job.set_time

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

  def get_job(job_id : String)
    response = get_job_content(job_id)

    case response
    when JSON::Any
      job = Job.new(response, job_id)
    else
      job = nil
    end

    return job
  end

  def get_account(my_email : String)
    query = {:index => "accounts", :type => "_doc", :id => my_email}
    response = JSON.parse({"_id" => my_email, "found" => false}.to_json)
    return response unless @client.exists(query)

    @client.get_source(query)
  end

  def search(index, query)
    results = @client.search({:index => index, :body => query})
    raise results unless results.is_a?(JSON::Any)

    return results["hits"]["hits"].as_a unless results.as_h.has_key?("error")

    puts results
    Array(JSON::Any).new
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
end
