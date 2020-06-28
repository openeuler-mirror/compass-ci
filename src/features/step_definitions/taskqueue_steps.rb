# frozen_string_literal: true

taskqueue_port = ENV['TASKQUEUE_PORT'] || 3060

Given('has a task') do |doc_string|
  @task = doc_string
end

When('call with post api {string} task') do |string|
  _, o = curl_post_result(taskqueue_port, string, @task, '-i')
  @result = get_http_status_and_content(o.readlines)
end

# @result = [Http_Status_code, Body_Json]
Then('return with task id > {int}') do |int|
  result = @result[1]['id']
  raise 'failed' unless result.to_i > int
end

Then('return with task id = {int}') do |int|
  result = @result[1]['id']
  raise 'failed' unless result.to_i == int
end
