#!/usr/bin/env ruby

#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'rest-client'

hostname = ARGV[0]
hosts_file = "/c/cci/lab-z9/hosts/#{hostname}"
devices_file = "/c/cci/lab-z9/devices/#{hostname}.json"

# Load and merge both data sources
hosts_data = YAML.load_file(hosts_file)
devices_data = JSON.parse(File.read(devices_file))
devices_data.delete "id"
merged_data = hosts_data.merge(devices_data).transform_keys(&:to_s)

# Send to the API
response = RestClient.post 'http://localhost:3000/register-host', 
  merged_data.to_json, content_type: :json

puts response.body
