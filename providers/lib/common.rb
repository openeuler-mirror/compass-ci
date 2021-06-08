# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def reboot(type, job_id)
  r, io = IO.pipe
  if type == 'dc'
    res = system("docker rm -f #{job_id}", out: io, err: io)
  else
    res = system("pkill #{job_id}", out: io, err: io)
  end
  io.close

  msg = []
  r.each_line { |l| msg << l.chomp }
  return res, msg.join(';')
end

def report_event(info, res, msg)
  data = { 'msg' => msg, 'res' => res }
  data.merge!(info)
  data['state'] = 'reboot_testbox'
  cmd = "curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'"
  system cmd
end
