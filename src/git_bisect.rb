# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'threadpool'
require_relative './git-bisect/bisect_worker'

pool = ThreadPool.new(10)
loop do
  10.times do
    pool.process do
      begin
        puts 'start consume'
        bisect_worker = BisectWorker.new
        bisect_worker.consume_bisect
      rescue StandardError => e
        puts e.message
        puts e.backtrace.inspect
      end
    end
  end
  sleep(600)
end
