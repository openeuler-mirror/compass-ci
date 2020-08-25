# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'json'

require_relative './constants'
require_relative './find-commit/git_bisect'
require_relative '../../lib/taskqueue_client'
require_relative '../../lib/mail_bisect_result'

# consume assister task queue
class Delimiter
  def initialize
    @tq = TaskQueueClient.new
  end

  def start_delimit
    # consume delimiter task queue
    task = consume_delimiter_queue
    return unless task

    # find first bad commit based on the task
    git_bisect = GitBisect.new task
    result = git_bisect.find_first_bad_commit

    # send mail
    mbr = MailBisectResult.new result
    mbr.create_send_email
  end

  private

  def consume_delimiter_queue
    response = @tq.consume_task(DELIMITER_TASK_QUEUE)
    return unless response.code == 200

    body = JSON.parse(response.body).to_hash
    return body
  end
end
