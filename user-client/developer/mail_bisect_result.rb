#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/mail_bisect_result'

# defaults
bisect_hash = {
  'repo' => 'pixz/pixz',
  'commit' => 'b0e2e5b8efc4c7f1994805797f65d77573d9649c',
  'job_id' => '59037',
  'error_id' => 'build-pkg.gcc:internal-compiler-error:Segmentation-fault(program-as)'
}

ARGV.each do |arg|
  k, v = arg.split '='
  bisect_hash[k] = v
end

MailBisectResult.new(bisect_hash).create_send_email
