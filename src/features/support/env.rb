# frozen_string_literal: true

require 'open3'
require 'json'
require 'yaml'
require 'pathname'

def curl_post_result(port, url, data, with_head = nil)
  curl_post_format = 'curl %s -X POST http://localhost:%d/%s -H "Content-Type: application/json" --data \'%s\''
  cmd = format(curl_post_format, with_head, port, url, data)
  Open3.popen3(cmd)
end

def curl_put_result(port, url, data, with_head = nil)
  curl_put_format = 'curl %s -X PUT http://localhost:%d/%s?%s'
  cmd = format(curl_put_format, with_head, port, url, data)
  Open3.popen3(cmd)
end

def curl_get_result(port, url, with_head = nil)
  curl_get_format = 'curl %s http://localhost:%d/%s'
  cmd = format(curl_get_format, with_head, port, url)
  Open3.popen3(cmd)
end
