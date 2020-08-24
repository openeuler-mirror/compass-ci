# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'threadpool'
require_relative './delimiter/delimiter'

pool = ThreadPool.new(10)
loop do
  10.times do
    pool.process do
      begin
        delimiter = Delimiter.new
        delimiter.start_delimit
      rescue StandardError => e
        puts e
      end
    end
  end
  sleep(30)
end
