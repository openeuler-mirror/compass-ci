#!/usr/bin/ruby
# frozen_string_literal: true

require 'elasticsearch'
require 'json'
require 'net/http'
require 'time'
require_relative '../container/defconfig.rb'
require_relative '../lib/constants.rb'
require_relative '../lib/constants-job.rb'

# Constants
N = ARGV[0]&.to_i || 100 # Default to 100 records
MANTICORE_HOST = 'localhost'
MANTICORE_PORT = 9308

# Connect to Elasticsearch
def connect_elasticsearch(host:, user:, password:)
  Elasticsearch::Client.new(
    hosts: ["#{host}:9200"],
    user: user,
    password: password,
    scheme: 'http'
  )
end

# Fetch last N accounts from Elasticsearch
def fetch_last_n_accounts(es:, n:)
  response = es.search(index: 'accounts', body: {
    sort: [{ my_account: { order: 'desc' } }],
    size: n
  })
  response['hits']['hits'].map { |hit| hit['_source'] }
end

# Transform Elasticsearch account to Manticore format
def transform_account(account)
  manti = {}

  # Direct fields
  manti[:id] = hash_string_to_i64(account['my_account'])
  manti[:gitee_id] = account['gitee_id'] || ''
  manti[:my_account] = account['my_account'] || ''
  manti[:my_commit_url] = account['my_commit_url'] || ''
  manti[:my_email] = account['my_email'] || ''
  manti[:my_login_name] = account['my_login_name'] || ''
  manti[:my_name] = account['my_name'] || ''
  manti[:my_token] = account['my_token'] || ''
  manti[:weight] = account['weight'] || 0
  manti[:create_time] = Time.now.to_i

  # Handle my_third_party_accounts
  if account['my_third_party_accounts']
    manti[:my_third_party_accounts] = account['my_third_party_accounts'].to_json
  end

  manti
end

# Insert account into Manticore
def insert_into_manticore(account)
  uri = URI.parse("http://#{MANTICORE_HOST}:#{MANTICORE_PORT}/insert")
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request['Content-Type'] = 'application/json'

  id = account.delete :id
  payload = {
    index: 'accounts',
    id: id,
    doc: account
  }

  request.body = payload.to_json
  response = http.request(request)
  if response.code.to_i == 200
    puts "Inserted account #{id}: #{response.code}"
  else
    puts "Failed to insert account #{id}: #{response.inspect}"
    puts account.inspect
  end
end

def hash_string_to_i64(input)
  # FNV-1a constants for 64-bit
  fnv_offset_basis = 0xcbf29ce484222325
  fnv_prime = 0x100000001b3

  hash = fnv_offset_basis

  input.each_byte do |byte|
    hash = hash ^ byte
    hash = (hash * fnv_prime) & 0xFFFFFFFFFFFFFFFF # Ensure 64-bit overflow
  end

  # Mask the result to ensure it's positive (clear the sign bit)
  positive_hash = hash & 0x7FFFFFFFFFFFFFFF

  # Convert to signed 64-bit integer
  if positive_hash > 0x7FFFFFFFFFFFFFFF
    positive_hash -= 0x10000000000000000
  end

  positive_hash
end

# Main script
names = Set.new %w[
  ES_USER
  ES_PASSWORD
]
config = relevant_service_authentication(names)
es = connect_elasticsearch(host: ES_HOST, user: config['ES_USER'], password: config['ES_PASSWORD'])
accounts = fetch_last_n_accounts(es: es, n: N)

accounts.each do |account|
  unless account['my_account']
    puts "skip incomplete account #{account}"
    next
  end
  manti_account = transform_account(account)
  insert_into_manticore(manti_account)
end

puts "\nMigration complete. #{accounts.size} accounts migrated."
