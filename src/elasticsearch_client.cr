# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "uri"
require "yaml"
require "json"
require "any_merge"
require "elasticsearch-crystal/elasticsearch/api"
require "elasticsearch-crystal/elasticsearch/api/utils"
require "./constants"
require "./job"
require "./lib/json_logger"
require "./manticore"

# -------------------------------------------------------------------------------------------
# save_job(job_content)
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

#= Database Backend Integration Policy
#
# This class provides transparent integration with both Elasticsearch and Manticore
# with the following behavior rules:
#
# 1. Read Policy:
#    - When both backends are enabled (has_es && has_manticore):
#      - All read operations use Elasticsearch exclusively
#      - Manticore is only used for write operations
#    - When only one backend is enabled, use the active backend
#
# 2. Write Policy:
#    - Create/Update/Delete operations write to both backends when enabled
#    - If both backends are enabled, operations are first attempted on Elasticsearch
#      then on Manticore
#    - Write failures in Manticore are logged but don't abort the operation
#
# 3. ID Handling:
#    - Manticore requires Int64 IDs while Elasticsearch uses String IDs
#    - Automatic conversion:
#      - Write operations: String IDs are converted to Int64 for Manticore
#      - Read operations: Int64 IDs are converted back to Strings when needed
#
# 4. Bulk Operations:
#    - Special handling for bulk operations due to format differences:
#      - Elasticsearch: Uses standard _bulk endpoint format
#      - Manticore: Converts to NDJSON format required by Manticore's /bulk endpoint
#    - Bulk operations are executed independently on each backend
#
# 5. Error Handling:
#    - Elasticsearch errors propagate normally
#    - Manticore errors are logged but don't affect Elasticsearch operations
#    - Failed Manticore operations don't roll back Elasticsearch changes
#
# 6. Configuration:
#    - Controlled through Sched.options flags:
#      - has_es: Enable Elasticsearch backend
#      - has_manticore: Enable Manticore backend
#    - When both are enabled, Elasticsearch remains primary for reads
#
# 7. Implementation Notes:
#    - Maintains original Elasticsearch API compatibility
#    - Manticore operations are optional extensions
#    - Conversion between database formats is handled transparently
#    - Bulk operation translation handles:
#      - create → Manticore create
#      - update → Manticore replace
#      - delete → Manticore delete
#=

class Elasticsearch::Client
  @host : String
  @port : Int32
  @settings : Hash(Symbol, String | Int32)
  @log : JSONLogger

  def initialize
    initialize(Sched.options.es_host, Sched.options.es_port)
  end

  def initialize(host : String, port : Int32)
    user = Sched.options.es_user
    password = Sched.options.es_password
    host = "#{user}:#{URI.encode_www_form(password)}@#{host}" unless user.empty? && password.empty?

    @host = host
    @port = port
    @settings = {
      :host => host,
      :port => port,
      :manticore_host => Sched.options.manticore_host,
      :manticore_port => Sched.options.manticore_port
    }
    @client = Elasticsearch::API::Client.new(@settings)
    @log = JSONLogger.new
  end

  def insert_doc(index, doc)
    es_response = nil
    manticore_response = nil

    if Sched.options.should_write_es
      content = doc.to_json_any
      es_response = es_create_doc(index, doc.id_es, content)
    end

    if Sched.options.should_write_manticore
      content = doc.to_manticore
      content.delete "id"   # avoid manticore 409 "column 'id' specified twice" error
      manticore_response = Manticore::Client.insert_by_id(index, doc.id64, content)
    end

    es_response || manticore_response
  end

  # caution: pass full doc to replace old doc as a whole
  def replace_doc(index, doc)
    es_response = nil
    manticore_response = nil

    if Sched.options.should_write_es && index != "hosts"
      content = doc.to_json_any
      es_response = es_update_doc(index, doc.id_es, content)
    end

    if Sched.options.should_write_manticore
      content = doc.to_manticore
      manticore_response = Manticore::Client.replace_by_id(index, doc.id64, content)
    end

    es_response || manticore_response
  end

  # caution: manticore only supports in-place updating row-wise attributes,
  # like numbers
  def update_doc(index, partial_doc)
    es_response = nil
    manticore_response = nil

    if Sched.options.should_write_es
      content = partial_doc.to_json_any
      es_response = es_update_doc(index, partial_doc.id_es, content)
    end

    if Sched.options.should_write_manticore
      content = partial_doc.to_manticore
      manticore_response = Manticore::Client.update_by_id(index, partial_doc.id64, content)
    end

    es_response || manticore_response
  end

  private def es_create_doc(index : String, id : Int64|String, job_content : JSON::Any)
    @client.create({
      :index => index, :type => "_doc",
      :refresh => "wait_for",
      :id => id,
      :body => job_content,
    })
  end

  private def es_update_doc(index : String, id : Int64|String, job_content : JSON::Any)
    # only called on Sched.options.should_write_es
    @client.update({
      :index => index, :type => "_doc",
      :refresh => "wait_for",
      :id => id,
      :body => {:doc => job_content},
    })
  end

  def query_host(hostname)
    begin
      results = self.select("hosts", {"hostname" => hostname})
      return nil unless results

      results[0]["_source"]
    rescue
      return nil
    end
  end

  def get_doc(id64 : Int64)
    if Sched.options.should_read_es
      response = @client.get_source({:index => "jobs", :type => "_doc", :id => id64.to_s})
      return response.as_h if response.is_a?(JSON::Any)
    end

    if Sched.options.should_read_manticore && !Sched.options.should_read_es
      begin
        response = Manticore::Client.get_source("jobs", id64)
        return nil if !response.is_a?(JSON::Any)
        response = Manticore.job_from_manticore(response.as_h)
      rescue
        return nil
      end
    end

    nil
  end

  def get_job(job_id : String)
    response = get_doc(job_id.to_i64)

    case response
    when JSON::Any
      job = JobHash.new(response.as_h, job_id)
    else
      job = nil
    end

    return job
  end

  def get_account(my_email : String)
    if Sched.options.should_read_es
      query = {:index => "accounts", :type => "_doc", :id => my_email}
      response = JSON.parse({"_id" => my_email, "found" => false}.to_json)
      return response unless @client.exists(query)

      result = @client.get_source(query)
      raise result unless result.is_a?(JSON::Any)
      result
    elsif Sched.options.should_read_manticore
      begin
        return Manticore::Client.get_source("accounts", my_email.to_i64)
      rescue
        return JSON.parse({"_id" => my_email, "found" => false}.to_json)
      end
    else
      nil
    end
  end

  def get_hit_total(index, query)
    if Sched.options.should_read_es
      results = @client.search({:index => index, :body => query})
      raise results unless results.is_a?(JSON::Any)

      total = results["hits"]["total"]["value"].to_s.to_i32
      id = total >= 1 ? results["hits"]["hits"][0]["_source"]["id"] : 0
      return total, id
    elsif Sched.options.should_read_manticore
      begin
        # expect the caller to define query["index"]
        response = Manticore::Client.search(query)
        results = JSON.parse(response.body)
        total = results["hits"]["total"].to_s.to_i32
        id = total >= 1 ? results["hits"]["hits"][0]["_id"].to_s : 0
        return total, id
      rescue
        return 0, 0
      end
    else
      return 0, 0
    end
  end

  def search(index : String, query, ignore_error = true)
    if Sched.options.should_read_es
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
    elsif Sched.options.should_read_manticore
      begin
        case query
        when Hash(String, JSON::Any)
          query["index"] = JSON::Any.new index
        when Hash(String, String)
          query["index"] = index
        else
          query["index"] = index
        end
        response = Manticore::Client.search(query)
        results = JSON.parse(response.body)["hits"]["hits"].as_a
        if index == "jobs"
          results = Manticore.jobs_from_manticore(results)
        end
        return results
      rescue e
        @log.error(e)
        return Array(JSON::Any).new
      end
    else
      return Array(JSON::Any).new
    end
  end

  def search_by_fields(index : String, kvs : Hash, size=10, source=Array(String).new, ignore_error = true)
    if Sched.options.should_read_es
      must = Array(Hash(String, Hash(String, Hash(String, String)))).new
      kvs.each do |field, value|
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
    elsif Sched.options.should_read_manticore
      begin
        must = Array(Hash(String, Hash(String, Hash(String, String)))).new
        kvs.each do |field, value|
          must << {"equals" => {field.to_s => value.to_s}}
        end
        real_query = {
          "_source" => source,
          "limit" => size,
          "query" => {
            "bool" => {
              "must" => must
            }
          }
        }
        response = Manticore::Client.search(real_query)
        results = JSON.parse(response.body)
        return Manticore.jobs_from_manticore(results["hits"]["hits"].as_a)
      rescue e
        @log.error("Manticore search_by_fields failed: #{e.message}")
        return Array(JSON::Any).new
      end
    else
      return Array(JSON::Any).new
    end
  end

  def delete(index, id)
    es_response = @client.delete({:index => index, :type => "_doc", :id => id}) if Sched.options.should_write_es

    if Sched.options.should_write_manticore
      begin
        Manticore::Client.delete(index, id.to_i64)
      rescue e
        @log.error("Manticore delete failed: #{e.message}")
      end
    end

    es_response
  end

  def build_query_string(query_hash : Hash(String, String), seporator : String, quote : Bool) : String
    # Filter out nil values and map each key-value pair to "key=value"
    conditions = query_hash.compact_map do |key, value|
      next if value.nil?
      if quote
        "#{key}='#{value}'"
      else
        "#{key}=#{value}"
      end
    end

    conditions.join(seporator)
  end

  def select(index : String, matches : Hash(String, String), fields : String = "*", others : String = "")
    if Sched.options.should_read_manticore
      match = build_query_string(matches, " ", false)
      fields = Manticore.filter_sql_fields(fields)
      match = Manticore.filter_sql_fields(match)
      others = Manticore.filter_sql_fields(others)
      sql_cmd  = URI.encode_www_form("SELECT #{fields} FROM #{index} WHERE MATCH('#{match}') #{others}")
      host_port = "#{@settings[:manticore_host]}:#{@settings[:manticore_port]}"
      response = perform_one_request(host_port, "sql", nil, "POST", "query=" + sql_cmd)
      body = response.body

      # Filter the SQL result if fields are not '*'
      body = Manticore.filter_sql_result(body) if fields != '*'

      json_hash = JSON.parse(body).as_h
      if json_hash.has_key? "error"
        error_message = json_hash["error"]
        raise "Manticore SQL Error: #{error_message} sql_cmd is #{sql_cmd}"
      end

      # Parse the JSON response and extract the results
      results = json_hash["hits"]["hits"].as_a
      results = Manticore.jobs_from_manticore(results)
      return results
    end

    if Sched.options.should_read_es && index != "hosts"
      # `path=_nlpcn/sql` refers to lib/es_client.rb opendistro_sql()
      # can verify with "cci select" command
      match = build_query_string(matches, " AND ", true)
      sql_cmd  = "SELECT #{fields} FROM #{index} WHERE #{match} #{others}"
      host_port = "#{@settings[:host]}:#{@settings[:port]}"
      response = perform_one_request(host_port, "_nlpcn/sql", nil, "POST", sql_cmd)
      body = response.body

      json_hash = JSON.parse(body).as_h
      if json_hash.has_key? "error"
        error_message = json_hash["error"]
        raise "ElasticSearch SQL Error: #{error_message} sql_cmd is #{sql_cmd}"
      end

      return results = json_hash["hits"]["hits"].as_a
    end

    results = Array(JSON::Any).new
  end

  def count_groups(index : String, dimension : String, matches : Hash(String, String)) : Hash(String, Int32)
    results = self.select(index, matches, "#{dimension}, count(*)", "GROUP BY #{dimension}")
    results.each_with_object({} of String => Int32) do |hit, hash|
      key = hit["_source"][dimension].to_s
      count = hit["_source"]["count(*)"].as_i
      hash[key] = count
    end
  end

  def perform_one_request(host_port, path, params, method, post_data)
    endpoint = "http://#{host_port}/#{path}"
    if params
      endpoint += "?#{params}"
    end

    if method == "GET"
      response = HTTP::Client.get(endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
    elsif method == "POST"
      response = HTTP::Client.post(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
    elsif method == "PUT"
      response = HTTP::Client.put(url: endpoint, body: post_data)
    elsif method == "DELETE"
      response = HTTP::Client.delete(url: endpoint)
    elsif method == "HEAD"
      response = HTTP::Client.head(url: endpoint)
    else
      raise "unknown HTTP method #{method}"
    end
    return response
  end

  def bulk(body : String, has_id : Bool = true)
    method = "POST"

    # Manticore bulk API strategy:
    # - Convert "update" actions to "replace" (Manticore uses replace for updates)
    # - Convert "_index" field to "index" (Manticore's field naming)
    if Sched.options.should_write_manticore && has_id
      endpoint = "http://#{Sched.options.manticore_host}:#{Sched.options.manticore_port}/bulk"
      modified_body = body.gsub(/"update":/, "\"replace\":")
                         .gsub(/"_index":/, "\"index\":")
      perform_bulk_request(endpoint, modified_body)
    end

    # Elasticsearch bulk API strategy:
    # - Convert payload to NDJSON format with proper action metadata
    # - Ensure "_index" field exists and doc content is properly structured
    if Sched.options.should_write_es
      endpoint = "http://#{@host}:#{@port}/_bulk"
      converted_body = es_bulkify(body)
      perform_bulk_request(endpoint, converted_body)
    end
  end

  # Convert an array of body into Elasticsearch format
  # Input: [
  # { :update => { :index => "1", :_id => "1", :doc => { :title => "update"}}},
  # { :create => { :index => "2", :_id => "2", :doc => { :title => "create"}}}
  # ]
  #
  # Output:
  # {"update":{"_index":"1","_id":"1"}}
  # { "doc": {"title":"update"}}
  # {"create":{"_index":"2","_id":"2"}}
  # {"title":"create"}
  #
  def es_bulkify(body)
    parsed_body = JSON.parse(body)
    return body unless parsed_body.is_a?(Array)

    tmp = [] of String
    parsed_body.each do |item|
      # Convert non-hash items directly to JSON
      unless item.is_a?(Hash)
        tmp << item.to_json
        next
      end

      action_type = item.keys.first
      action_meta = item[action_type].as_h.dup

      # Convert Elasticsearch metadata format:
      # - Rename "index" => "_index" if present
      if action_meta.has_key?("index")
        action_meta["_index"] = action_meta.delete("index")
      end

      # Extract document content if exists
      doc = action_meta.delete("doc")

      # Add action line with metadata
      tmp << {action_type => action_meta}.to_json

      # Add document content line if present
      next unless doc

      # For update actions, wrap doc in {"doc": ...} structure
      tmp << (action_type == "update" ? {"doc" => doc} : doc).to_json
    end

    # Join with newlines and add final empty line for NDJSON compliance
    tmp << ""
    tmp.join("\n")
  end

  def perform_bulk_request(endpoint, body)
    headers = HTTP::Headers{"Content-Type" => "application/x-ndjson"}
    response = HTTP::Client.post(endpoint, headers: headers, body: body)
    JSON.parse(response.body)
  end

end
