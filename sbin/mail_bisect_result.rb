#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/mail_bisect_result'

# defaults
bisect_hash = {
  'repo' => 'pixz/pixz.git',
  'commit' => 'b0e2e5b8efc4c7f1994805797f65d77573d9649c'
}

ARGV.each do |arg|
  k, v = arg.split '='
  bisect_hash[k] = v
end

mail_delimiter_result(bisect_hash)
