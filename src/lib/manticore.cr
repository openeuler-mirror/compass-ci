require "http/client"
require "json"
require "./constants-manticore.cr"

module Manticore
  HOST = ENV["MANTICORE_HOST"]? || "localhost"
  PORT = (ENV["MANTICORE_PORT"]? || 9308).to_i

  # Field lists
  MANTI_STRING_FIELDS = %w[suite category my_account testbox arch osv]
  MANTI_INT64_FIELDS = %w[id submit_time boot_time running_time finish_time]
  MANTI_INT32_FIELDS = %w[boot_seconds run_seconds istage ihealth]
  MANTI_FULLTEXT_FIELDS = %w[
    tbox_type build_type spec_file_name
    suite category queue all_params_md5 pp_params_md5 testbox tbox_group hostname
    host_machine group_id os osv arch os_version
    pr_merge_reference_name my_account job_stage job_health
    last_success_stage os_project package build_id os_variant
  ]
  MANTI_FULLTEXT_ARRAY_FIELDS = %w[
    target_machines
  ]
  # = MANTI_FULLTEXT_FIELDS + MANTI_FULLTEXT_ARRAY_FIELDS - MANTI_STRING_FIELDS
  MANTI_JSON_PROPERTIES = %w[
    tbox_type build_type spec_file_name
    queue all_params_md5 pp_params_md5 tbox_group hostname
    host_machine group_id os os_arch os_version
    pr_merge_reference_name job_stage job_health
    last_success_stage os_project package build_id os_variant
    target_machines
  ]

  def self.filter_sql_fields(sql : String) : String
    regex = /\b(#{Regex.union(MANTI_JSON_PROPERTIES)})\b/
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
    def self.run_sql(sql : String) : HTTP::Client::Response
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

    # curl -sX POST http://localhost:9308/insert  -d '
    # {
    #   "table":"products",
    #   "id":1,
    #   "doc":
    #   {
    #     "title" : "Crossbody Bag with Tassel",
    #     "price" : 19.85
    #   }
    # }
    # '
    def self.insert_by_id(index : String, id : Int64, doc : JSON::Any | Hash) : Bool
      json_by_id("/insert", index, id, doc)
    end

    # curl -sX POST http://localhost:9308/replace -H "Content-Type: application/x-ndjson" -d '
    # {
    #   "table":"products",
    #   "id":1,
    #   "doc":
    #   {
    #     "title":"product one",
    #     "price":10
    #   }
    # }
    # '
    def self.replace_by_id(index : String, id : Int64, doc : JSON::Any | Hash) : Bool
      json_by_id("/replace", index, id, doc)
    end

    # curl -sX POST http://localhost:9308/update  -d '
    # {
    #   "table":"test",
    #   "id":1,
    #   "doc":
    #    {
    #      "gid" : 100,
    #      "price" : 1000
    #    }
    # }
    def self.update_by_id(index : String, id : Int64, doc : JSON::Any | Hash) : Bool
      json_by_id("/update", index, id, doc)
    end

    def self.json_by_id(api : String, index : String, id : Int64, doc : JSON::Any | Hash) : Bool
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      body = {
        "index" => index,
        "id"    => id,
        "doc"   => doc
      }.to_json
      response = client.post(api, headers: headers, body: body)
      raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      result.as_h.has_key? "errors"
    end

    # Manticore's "POST /update" is partial replace, it has limitation that can
    # only update row-wise attributes. In Compass we only update number fields
    # efficiently by this API. We won't use /_update API since it requires
    # Manticore Buddy, which is not as stable and performant.
    # API example: UPDATE products SET enabled=0 WHERE id=10;
    def self.update_by_query(index : String, query : String, kv : String) : Bool
      run_sql("UPDATE #{index} SET #{kv} WHERE #{query};")
    end

    # API example: REPLACE INTO products VALUES(1, "document one", 10);
    def self.replace(index : String, values : String) : Bool
      run_sql("REPLACE INTO #{index} VALUES (#{values})")
    end

    def self.delete(index : String, id : Int64) : Bool
      client = HTTP::Client.new(HOST, PORT)
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      body = {
        "index" => index,
        "id"    => id
      }.to_json
      response = client.post("/delete", headers: headers, body: body)
      # raise "HTTP error: #{response.status_code}" unless response.status.success?

      result = JSON.parse(response.body)
      result.has_key? "errors"
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

  module FullTextWords

    def self.process_word(word : String) : String?
      # Trim leading/trailing non-alphanumeric characters
      trimmed = word.gsub(/\(R\)\z/, "")
      trimmed = trimmed.gsub(/^[^A-Za-z0-9]*|[^A-Za-z0-9]*$/, "")

      # Exclude empty or symbol-only words
      return nil if trimmed.empty? || trimmed =~ /\A[^[:alnum:]]*\z/
      trimmed
    end

    def self.is_number?(word : String) : Bool
      if word =~ /\A[+-]?(?:\d+\.?\d*|\.\d+)\z/
        true
      else
        false
      end
    end

    def self.is_unit?(word : String) : Bool
      if word =~ /\A[[:alpha:]]+\z/
        true
      else
        false
      end
    end

    def self.break_full_text_words(input : String) : Array(String)
      words = input.split(/\s+/)
      processed = [] of String
      words.each do |word|
        result = process_word(word)
        processed << result if result
      end

      # Merge numbers with units
      i = 0
      while i < processed.size
        current = processed[i].as(String)
        if is_number?(current) && i + 1 < processed.size && is_unit?(processed[i + 1])
          merged = current + processed[i + 1].as(String)
          processed[i] = merged
          processed.delete_at(i + 1)
        end
        i += 1
      end

      processed
    end

    def self.flatten_hash(hash : Hash(String, JSON::Any), prefix = "", result = Hash(String, JSON::Any).new) : Hash(String, JSON::Any)
      hash.each do |key, value|
        current_key = prefix.empty? ? key : "#{prefix}.#{key}"

        if (nested_hash = value.as_h?)
          # Recursively flatten nested hashes
          flatten_hash(nested_hash, current_key, result)
        elsif (array = value.as_a?)
          # Separate array elements into hashes and primitives
          hashes = array.select { |item| item.as_h? }
          primitives = array.reject { |item| item.as_h? }

          # Flatten each hash in the array
          hashes.each do |item|
            flatten_hash(item.as_h, current_key, result)
          end

          # Collect primitives into an array under the current key
          unless primitives.empty?
            primitive_values = primitives.map { |p| JSON::Any.new(p.raw) }
            add_to_result(result, current_key, JSON::Any.new(primitive_values))
          end
        else
          # Handle primitive values
          add_to_result(result, current_key, value)
        end
      end
      result
    end

    private def self.add_to_result(result, key, value)
      existing = result[key]?
        if existing.nil?
          result[key] = value
      else
        # Convert existing value to an array if not already
        existing_array = existing.as_a? || [existing]
        new_value = value.as_a? || [value]
        result[key] = JSON::Any.new(existing_array + new_value)
      end
    end

    def self.create_full_text_kv(host_info : Hash(String, JSON::Any), keys : Array(String)) : Array(String)
      flattened_hash = flatten_hash(host_info)
      full_text_kv = [] of String

      key_regex = %r{\A(#{keys.join('|')})\.}

      flattened_hash.each do |key, values|
        next unless key =~ key_regex
        if (array = values.as_a?)
          array.each do |value|
            break_full_text_words(value.as_s).each do |word|
              full_text_kv << "#{key}=#{word}"
            end
          end
        else
          break_full_text_words(values.as_s).each do |word|
            full_text_kv << "#{key}=#{word}"
          end
        end
      end

      full_text_kv.uniq
    end

  end
end
