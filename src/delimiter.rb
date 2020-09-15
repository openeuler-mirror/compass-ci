# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative './delimiter/constants'
require_relative './delimiter/delimiter'

START_PROCESS_COUNT.times do
  begin
    Process.fork do
      delimiter = Delimiter.new
      delimiter.start_delimit
    end
  rescue StandardError => e
    puts e
  end
end

sleep()
