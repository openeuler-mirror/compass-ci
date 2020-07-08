# frozen_string_literal: true

sched_port = ENV['SCHED_PORT'] || 3000
job_file_path = Pathname.new("#{__FILE__}/../../jobs").realpath

Given('prepared a job {string}') do |string|
  @job = YAML.safe_load(File.read("#{job_file_path}/#{string}")).to_json
end

# submit_job
When('call with API: post {string} job from add_job.sh') do |string|
  _, o = curl_post_result(sched_port, string, @job)
  @result = o.gets
end

Then('return with job id') do
  @id_submited = @result.to_i
  puts "Submit job (id = #{@id_submited})"
  raise 'Failed to submit_job' unless @id_submited.positive?
end

# set_host_mac
# host_mac => "vm-hi1620-2p8g-chief => ef-01-02-03-04-05"
Given('call with API: put {string} {string}') do |url, host_mac|
  host_mac_params = host_mac.split(' ')
  url_with_params = "#{url}?hostname=#{host_mac_params[0]}\\&mac=#{host_mac_params[2]}"
  _, o = curl_put_result(sched_port, url_with_params)
  @result = o.gets
  raise "Failed to #{url}" unless @result == 'Done'
end

# boot.ipxe/mac/ef-01-02-03-04-05
When('call with API: get {string}') do |url|
  _, o = curl_get_result(sched_port, url)
  @result = ''
  o.each_line { |line| @result += line }
end

Then('return with basic ipxe boot parameter and initrd and kernel') do
  result = @result.split("\n")
  len = result.size

  raise "Not start with #!ipxe, but #{result[0]}" unless result[0] == '#!ipxe'

  raise "Not end with boot, but #{result[len - 1]}" unless result[len - 1] == 'boot'

  (2..(len - 2)).each do |i|
    id = %r{.*/(\d+)/job}.match(result[i])
    puts "Check job (id = #{id[1]})" if id
  end

  (2..(len - 2)).each do |i|
    test_initrd_or_kernel(result[i])
  end
end
