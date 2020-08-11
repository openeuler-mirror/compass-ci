# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

taskqueue_port = ENV['TASKQUEUE_PORT'] || 3060

Given('has a task') do |doc_string|
  @task = doc_string
end

When('call with post api {string} task') do |url|
  _, o = curl_post_result(taskqueue_port, url, @task, '-i')
  @result = get_http_status_and_content(o.readlines)
end

# @result = [Http_Status_code, Body_Json]
Then('return with task id > {int}') do |task_id|
  result = @result[1]['id']
  raise 'failed' unless result.to_i > task_id
end

Then('return with task id = {int}') do |task_id|
  result = @result[1]['id']
  raise 'failed' unless result.to_i == task_id
end

When('call with put api {string}') do |url|
  _, o = curl_put_result(taskqueue_port, url, '-i')
  @result = get_http_status_and_content(o.readlines)
end

Then('return with task tbox_group == {string}') do |tbox_group|
  result = @result[1]['tbox_group']
  raise 'failed' unless result == tbox_group
end

When('call with put api {string} and previous get id') do |url|
  url += @result[1]['id'].to_s
  _, o = curl_put_result(taskqueue_port, url, '-i')
  @result = get_http_status_and_content(o.readlines)
end

Then('return with http status_code = {int}') do |http_status_code|
  result = @result[0]
  raise 'failed' unless result.to_i == http_status_code
end
