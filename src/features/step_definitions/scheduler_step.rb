# frozen_string_literal: true

sched_port = ENV['SCHED_PORT'] || 3000
job_file_path = Pathname.new("#{__FILE__}/../../jobs").realpath

Given('prepared a job {string}') do |string|
  @job = YAML.safe_load(File.read("#{job_file_path}/#{string}")).to_json
end

When('call with API: post {string} job') do |string|
  _, o = curl_post_result(sched_port, string, @job)
  @result = o.gets
end

Then('return with job id') do
  raise 'Failed to submit_job' unless @result.to_i.positive?
end
