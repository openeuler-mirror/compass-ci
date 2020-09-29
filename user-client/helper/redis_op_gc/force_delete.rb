# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'json'
require_relative './basic_env'

# force delete for job (with job_id)
# - taskqueue hash key: "queues/sched/*/reday?in_process?idle?uuid..."
# - taskqueue hash key: "queues/id2content"
# - scheduler hash key: "sched/id2job"
class ForceDelete
  def initialize(id)
    @task_id = id.chomp
  end

  def run
    fd4jobqueue
    gc4taskqueue
    gc4scheduler
  end

  def fd4jobqueue
    task_content = get_taskqueue_content4id(nil, @task_id)
    return unless task_content

    queue_name = task_content['queue']
    cmd = "#{CMD_BASE} queues/#{queue_name} , zrem #{@task_id}"
    `#{cmd}`.chomp
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
