require "http/client"
require "json"

module Manticore
  HOST = ENV["MANTICORE_HOST"]? || "localhost"
  PORT = (ENV["MANTICORE_PORT"]? || 9308).to_i

  ES_PROPERTIES = %w[
    tbox_type build_type spec_file_name
    suite category queue all_params_md5 pp_params_md5 testbox tbox_group hostname
    host_machine group_id os osv os_arch os_version
    pr_merge_reference_name my_account job_stage job_health
    last_success_stage os_project package build_id os_variant
    target_machines
  ]

  def self.filter_sql_fields(sql : String) : String
    regex = /\b(#{Regex.union(ES_PROPERTIES)})\b/
    sql.gsub(regex) { |m| "j.#{$1}" }.gsub(/j\.j\./, "j.")
  end

  def self.filter_sql_result(body : String) : String
    body.gsub(/"j\.([^" ]+)":/) { "\"#{$1}\":" }
  end

  def self.job_from_manticore(job_content : Hash(String, JSON::Any))
    job_content.merge! job_content.delete("j").not_nil!.as_h if job_content.has_key? "j"
    job_content
  end

  def self.jobs_from_manticore(hits : Array(JSON::Any))
    hits.each do |hit|
      job_content = hit.as_h["_source"].as_h
      job_from_manticore(job_content)
    end
    hits
  end

  # for converting elasticsearch string id to manticore id
  # normally used as a workaround for fast transition
  def self.hash_string_to_i64(input : String) : Int64
    # FNV-1a constants for 64-bit
    fnv_offset_basis = 0xcbf29ce484222325_u64
    fnv_prime = 0x100000001b3_u64

    hash = fnv_offset_basis

    input.each_byte do |byte|
      hash = hash ^ byte.to_u64
      hash = hash &* fnv_prime
    end

    # Mask the result to ensure it's positive (clear the sign bit)
    positive_hash = hash & 0x7FFFFFFFFFFFFFFF_u64

    # Convert to Int64
    positive_hash.to_i64
  end

  module Client
    def self.sql(sql : String) : HTTP::Client::Response
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      response = client.post("/sql", headers: headers, form: {"mode" => "raw", "query" => sql})
      response
    end

    def self.select(sql : String) : HTTP::Client::Response
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      response = client.post("/sql", headers: headers, form: {"query" => sql})
      response
    end

    def self.search(query) : HTTP::Client::Response
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      response = client.post("/search", headers: headers, body: query.to_json)
      response
    end

    def self.exists(index : String, id : Int64) : Bool
      sql = "SELECT id FROM #{index} WHERE id = #{id}"
      begin
        response = Client.select(sql)
        return false unless response.status.success?

        result = JSON.parse(response.body)
        result["hits"]["total"].as_i > 0
      rescue
        false
      end
    end

    def self.get_source(index : String, id : Int64) : JSON::Any
      sql = "SELECT * FROM #{index} WHERE id = #{id}"
      response = Client.select(sql)
      raise "Request failed: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)

      if result["hits"]["total"].as_i == 0
        raise "Document not found"
      end

      result["hits"]["hits"][0]["_source"]
    end

    def self.replace(index : String, id : Int64, doc : JSON::Any | Hash) : JSON::Any
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      body = {
        "index" => index,
        "id"    => id,
        "doc"   => doc
      }.to_json
      response = client.post("/replace", headers: headers, body: body)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      if result["errors"]?
        raise "Update error: #{result}"
      end
      result
    end

    # This is partial replace, not Manticore's "POST /update", which won't be
    # used in our project due to it can only work on row-wise attribute values.
    # Partial replace requires Manticore Buddy. If it doesn't work, make sure Buddy is installed.
    def self.update(index : String, id : Int64, doc : JSON::Any | Hash) : JSON::Any
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      response = client.post("/#{index}/_update/#{id}", headers: headers, body: doc.to_json)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      if result["errors"]?
        raise "Update error: #{result}"
      end
      result
    end

    def self.create(index : String, id : Int64, doc : JSON::Any | Hash) : JSON::Any
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      body = {
        "index" => index,
        "id"    => id,
        "doc"   => doc
      }.to_json
      response = client.post("/insert", headers: headers, body: body)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      if result["errors"]?
        raise "Create error: #{result}"
      end
      result
    end

    def self.delete(index : String, id : Int64) : JSON::Any
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      body = {
        "index" => index,
        "id"    => id
      }.to_json
      response = client.post("/delete", headers: headers, body: body)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      if result["errors"]?
        raise "Delete error: #{result}"
      end
      result
    end

    def self.bulk(ndjson : String) : JSON::Any
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/x-ndjson"}
      response = client.post("/bulk", headers: headers, body: ndjson)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      if result["errors"]?
        raise "Bulk error: #{result}"
      end
      result
    end
  end
end
