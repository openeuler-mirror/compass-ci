# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

raise 'Need define env CCI_SRC' unless ENV['CCI_SRC'] != ''

CCI_REDIS_OP_DIR ||= "#{ENV['CCI_SRC']}/user-client/helper/redis_op"
CMD_BASE ||= "redis-cli --eval #{CCI_REDIS_OP_DIR}/key_cmd_params.lua "

GC4ID = 'Garbage collection for id'
GCN4ID = 'Doing nothing for id'
NO_DATA = 'No data id'
MANUAL_DELETED = 'Manual deleted id'
ALIVE_TOO_LONG = 'Alive too long id'

def set_progress(index, max, char = '#')
  percent = index * 100 / max
  print (char * (percent / 2.5).floor).ljust(40, ' '), " #{percent}%\r"
  $stdout.flush
end

def get_taskqueue_content4id(content, id)
  if content.nil?
    cmd = "#{CMD_BASE} queues/id2content , hget #{id}"
    content = `#{cmd}`.chomp
  end

  return nil if content.nil?

  return nil if content.length.zero?

  return JSON.parse(content)
end
