# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'open3'
require 'json'
require 'yaml'
require 'pathname'
require 'fileutils'

def curl_post_result(port, url, data, with_head = nil)
  curl_post_format = 'curl %s -X POST http://localhost:%d/%s -H "Content-Type: application/json" --data \'%s\''
  cmd = format(curl_post_format, with_head, port, url, data)
  Open3.popen3(cmd)
end

def curl_put_result(port, url, with_head = nil)
  curl_put_format = 'curl %s -X PUT http://localhost:%d/%s'
  cmd = format(curl_put_format, with_head, port, url)
  Open3.popen3(cmd)
end

def curl_get_result(port, url, with_head = nil)
  curl_get_format = 'curl %s http://localhost:%d/%s'
  cmd = format(curl_get_format, with_head, port, url)
  Open3.popen3(cmd)
end

# raw exmples:
# [
#  "HTTP/1.1 200 OK\r\n",
#  "Connection: keep-alive\r\n", "X-Powered-By: Kemal\r\n",
#  "Content-Type: text/html\r\n", "Content-Length: 10\r\n", "\r\n",
#  "{\"id\":11}\n"
# ]
def get_http_status_and_content(raw)
  array_size = raw.size
  status_code = raw[0].match(/ (\d+) /)
  status_code = status_code[1].to_i

  content_json = case status_code
                 when 200
                   JSON.parse(raw[array_size - 1])
                 end

  [status_code, content_json]
end

def test_initrd(initrd)
  filename_download = %r{.*/(.*)}.match(initrd)[1]
  saved_filename = "/tmp/#{filename_download}"
  cmd = "curl -# -o #{saved_filename} #{initrd}"
  Open3.popen3(cmd)

  return unless File.size(saved_filename) < 1000

  lines = File.readlines(saved_filename)
  raise "Faile to get initrd #{initrd}" if lines[0].chomp == '<html>'
end

def test_kernel(kernel_params_list)
  # need more detail implementation
  raise 'Too few of kernel parameters' if kernel_params_list.size < 10
end

def test_initrd_or_kernel(cmd_line)
  puts "Chech #{cmd_line}"
  cmd_line_list = cmd_line.split(' ')
  case cmd_line_list[0]
  when 'initrd'
    test_initrd(cmd_line_list[1])
  when 'kernel'
    test_kernel(cmd_line_list)
  else
    puts "No check to #{cmd_line}"
  end
end
