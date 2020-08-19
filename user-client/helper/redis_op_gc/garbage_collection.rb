# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative './abnormal_id_detect'

# garbage collection for redis key (not exists field)
# - taskqueue hash key: "queues/id2content"
# - scheduler hash key: "sched/id2job"
class GarbageCollection
  def initialize(id, days = 3, content = nil)
    @task_id = id
    @day_number = days

    @content = get_taskqueue_content4id(content, id)
  end

  def run
    abn = AbnormalIdDetect.new(@task_id, @day_number, @content.to_json)
    result = abn.check
    case result.gsub(/=.*/, '')
    when MANUAL_DELETED
      gc4taskqueue
      gc4scheduler
      GC4ID + "=#{@task_id}"
    when ALIVE_TOO_LONG
      'No define process now'
    else
      GCN4ID + "=#{@task_id}"
    end
  end

  def gc4taskqueue
    cmd = "#{CMD_BASE} queues/id2content , hdel #{@task_id}"
    `#{cmd}`.chomp
  end

  def gc4scheduler
    cmd = "#{CMD_BASE} sched/id2job , hdel #{@task_id}"
    `#{cmd}`.chomp
  end
end
