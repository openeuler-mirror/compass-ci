#!/usr/bin/ruby
# frozen_string_literal: true

# This script migrates the last N jobs from Elasticsearch to Manticore Search.
# It reads job records from Elasticsearch, transforms them according to specific rules,
# and inserts them into Manticore Search via its HTTP JSON API.
#
# Data Structure and Conversion Design:
# - Elasticsearch job records are stored in a dynamic `job.json` structure.
# - Fields defined in the Elasticsearch mapping are searchable; others are not.
# - The script maps specific fields directly (e.g., `id`, `submit_time`).
# - Nested fields (`pp`, `ss`) are flattened into key-value pairs.
# - Remaining fields are concatenated into a searchable `full_text_kv` string.
# - The entire job is stored as JSON in the `j` field for reference.
#
# Example Elasticsearch job structure:
# {
#   "id": "10250125163738274",
#   "submit_time": "2025-01-25T16:37:38+0800",
#   "boot_time": "2025-01-25T16:37:49+0800",
#   "errid": ["dmesg.tstage.last", "kmsg.tstage.last"],
#   "pp": { "pkgbuild": { "pkgbuild_repo": "pkgbuild/aur-l/linux" } },
#   "suite": "pkgbuild",
#   "category": "functional",
#   ...
# }
#
# The transformed Manticore record:
# {
#   id: 10250125163738274,
#   submit_time: 1737815858, # Unix timestamp
#   boot_time: 1737815869,
#   errid: "dmesg.tstage.last kmsg.tstage.last",
#   full_text_kv: "pp.pkgbuild.pkgbuild_repo=pkgbuild/aur-l/linux suite=pkgbuild category=functional ...",
#   j: { ... } # Original job JSON
# }

require 'elasticsearch'
require 'json'
require 'net/http'
require 'time'
require_relative '../container/defconfig.rb'
require_relative '../lib/constants.rb'

# Constants
N = ARGV[0]&.to_i || 100 # Default to 100 records
MANTICORE_HOST = 'localhost'
MANTICORE_PORT = 9308

# Field lists
DIRECT_FIELDS = %w[id submit_time boot_time running_time finish_time].freeze
DURATION_FIELDS = %w[boot_seconds run_seconds].freeze
ES_PROPERTIES = %w[
  tbox_type build_type max_duration spec_file_name memory_minimum use_remote_tbox
  suite category queue all_params_md5 pp_params_md5 testbox tbox_group hostname
  host_machine target_machines group_id os osv os_arch os_version depend_job_id
  pr_merge_reference_name nr_run my_email my_account user job_stage job_health
  last_success_stage tags os_project package build_id os_variant start_time end_time
].freeze

# Connect to Elasticsearch
def connect_elasticsearch(host:, user:, password:)
  Elasticsearch::Client.new(
    hosts: ["#{host}:9200"],
    user: user,
    password: password,
    scheme: 'http'
  )
end

# Fetch last N jobs from Elasticsearch
def fetch_last_n_jobs(es:, n:)
  response = es.search(index: 'jobs', body: {
    sort: [{ submit_time: { order: 'desc' } }],
    size: n
  })
  response['hits']['hits'].map { |hit| hit['_source'] }
end

# Convert time string to Unix timestamp
def time_to_unix(time_str)
  Time.parse(time_str).to_i
rescue ArgumentError => e
  puts "Error parsing time: #{e.message}"
  nil
end

# Convert duration string (HH:MM:SS) to seconds
def duration_to_seconds(duration)
  return nil unless duration

  parts = duration.split(':').map(&:to_i)
  parts[0] * 3600 + parts[1] * 60 + parts[2]
rescue StandardError
  nil
end

# Process nested fields (pp, ss) into key-value pairs
def process_nested_fields(prefix, hash)
  return [] unless hash.is_a?(Hash)

  hash.flat_map do |k1, inner|
    next [] unless inner.is_a?(Hash)

    inner.map do |k2, v|
      "#{prefix}.#{k1}.#{k2}=#{v}"
    end
  end
end

# Transform Elasticsearch job to Manticore format
def transform_job(job)
  manti = {}

  # Direct fields
  DIRECT_FIELDS.each do |field|
    next unless job.key?(field)

    if field.end_with?('_time')
      manti[field.to_sym] = time_to_unix(job[field])
    else
      manti[field.to_sym] = job[field].to_i
    end
  end

  # Duration fields
  DURATION_FIELDS.each do |field|
    next unless job.key?(field)

    manti[field.to_sym] = duration_to_seconds(job[field])
  end

  # errid as space-separated string
  errid = job['errid']
  manti[:errid] = errid.is_a?(Array) ? errid.join(' ') : ''

  # Process nested fields (pp, ss)
  full_text_kv = []
  full_text_kv += process_nested_fields('pp', job['pp'])
  full_text_kv += process_nested_fields('ss', job['ss'])

  # Remaining fields
  ES_PROPERTIES.each do |field|
    next if DIRECT_FIELDS.include?(field) || DURATION_FIELDS.include?(field)
    next unless job.key?(field)

    value = job[field]
    value = value.join(' ') if value.is_a?(Array)
    full_text_kv << "#{field}=#{value}"
  end

  manti[:full_text_kv] = full_text_kv.join(' ')
  manti[:j] = job

  manti
end

# Insert job into Manticore
def insert_into_manticore(job)
  uri = URI.parse("http://#{MANTICORE_HOST}:#{MANTICORE_PORT}/insert")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request['Content-Type'] = 'application/json'

  id = job.delete :id
  payload = {
    index: 'jobs',
    id: id,
    doc: job
  }

  request.body = payload.to_json
  response = http.request(request)
  puts "Inserted job #{id}: #{response.code}"
end

# Main script
names = Set.new %w[
  ES_USER
  ES_PASSWORD
]
config = relevant_service_authentication(names)
es = connect_elasticsearch(host: ES_HOST, user: config['ES_USER'], password: config['ES_PASSWORD'])
jobs = fetch_last_n_jobs(es: es, n: N)

jobs.each do |job|
  manti_job = transform_job(job)
  insert_into_manticore(manti_job)
end

puts "\nMigration complete. #{jobs.size} jobs migrated."
