# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/sched"
require "../lib/json_logger"

# -------------------------------------------------------------------------------------------
# end_user:
# - restful API [post "/submit_job"] to submit a job to scheduler
# -- json formated [job] in the request data
#
# -------------------------------------------------------------------------------------------
# runner:
# - restful API [get "/boot.ipxe/mac/52-54-00-12-34-56"] to get a job for ipxe qemu-runner
#  -- when find then return <#!ipxe and job.cgz kernal initrd>
#  -- when no job return <#!ipxe no job messages>
#
# - restful API [put "/set_host_mac?hostname=myhostname&mac=ff-ff-ff-ff-ff-ff"] to report testbox's {mac => hostname}
# - restful API [get "/job_initrd_tmpfs/11/job.cgz"] to download job(11) job.cgz file
# - restful API [get "/~lkp/cgi-bin/lkp-jobfile-append-var"] report job var that should be append
# - restful API [get "/~lkp/cgi-bin/lkp-cluster-sync"] for nodes to request cluster state
# - restful API [get "/~lkp/cgi-bin/lkp-post-run" ] to move job from redis queue "sched/jobs_running" to "sched/extract_stats" and remove job from redis queue "sched/id2job"
#
# -------------------------------------------------------------------------------------------
# scheduler:
# - use [redis incr] as job_id, a 64bit int number
# - restful API [get "/"] default echo
#
module Scheduler
  VERSION = "0.2.0"
  logging false

  add_context_storage_type(Time::Span)

  before_all do |env|
    env.set "start_time", Time.monotonic
    env.response.headers["Connection"] = "close"
    env.create_log
    env.create_sched
    env.set "api", env.sched.get_api.to_s
  rescue e
    env.log.warn(e.inspect_with_backtrace)
  end

  after_all do |env|
    env.sched.etcd_close
    env.log.info({
      "from" => env.request.remote_address.to_s,
      "message" => "access_record"
    }.to_json) if env.response.status_code == 200
  rescue e
    env.log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  # echo alive
  get "/" do |env|
    env.sched.alive(VERSION)
  end

  # for XXX_runner get job
  #
  # /boot.ipxe/mac/${mac}
  # /boot.xxx/host/${hostname}
  # /boot.yyy/mac/${mac}
  get "/boot.:boot_type/:parameter/:value" do |env|
    env.sched.find_job_boot
  end

  ws "/ws/boot.:boot_type/:parameter/:value" do |socket, env|
    env.set "ws", true
    env.create_socket(socket)
    sched = env.sched

    spawn sched.find_job_boot

    socket.on_message do |msg|
      msg = JSON.parse(msg.to_s).as_h?
      (spawn env.channel.send(msg)) if msg
    end

    socket.on_close do
      sched.etcd_close
      (spawn env.channel.send({"type" => "close"})) unless env.get?("ws_state") == "normal"
    end
  end

  # /~lkp/cgi-bin/gpxelinux.cgi?hostname=:hostname&mac=:mac&last_kernel=:last_kernel
  get "/~lkp/cgi-bin/gpxelinux.cgi" do |env|
    env.sched.find_next_job_boot
  end

  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  post "/submit_job" do |env|
    env.sched.submit_job.to_json
  end

  # delete jobs from queue
  post "/cancel_jobs" do |env|
    env.sched.cancel_jobs.to_json
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'
  post "/report_event" do |env|
    env.sched.report_event.to_s
  end

  # extend the deadline
  # curl "http://localhost:3000/renew_deadline?job_id=1&time=100
  get "/renew_deadline" do |env|
    env.sched.renew_deadline.to_s
  end

  # get testbox deadline
  # curl "http://localhost:3000/get_deadline?testbox=xxx
  get "/get_deadline" do |env|
    env.sched.get_deadline.to_s
  end

  # get testbox info
  # curl "http://localhost:3000/get_testbox?testbox=xxx
  get "/get_testbox" do |env|
    env.sched.get_testbox.to_json
  end

  # file download server
  get "/job_initrd_tmpfs/:job_id/:job_package" do |env|
    env.sched.download_file
  end

  get "/download" do |env|
    env.sched.download
  end

  # client(runner) report its hostname and mac
  #  - when a runner pull jobs with it's mac infor, scheduler find out what hostname is it
  # /set_host_mac?hostname=$hostname&mac=$mac (mac like ef-01-02-03-04-05)
  # add a <mac> => <hostname>
  #
  # curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg&mac=00-01-02-03-04-05"
  put "/set_host_mac" do |env|
    env.sched.set_host_mac
  end

  # curl -X PUT "http://localhost:3000/set_host2queues?queues=vm-2p8g.aarch64&host=vm-2p8g.aarch64"
  put "/set_host2queues" do |env|
    env.sched.set_host2queues
  end

  # curl -X PUT "http://localhost:3000/del_host_mac?mac=00-01-02-03-04-05"
  put "/del_host_mac" do |env|
    env.sched.del_host_mac
  end

  # curl -X PUT "http://localhost:3000/del_host2queues?host=vm-2p8g.aarch64"
  put "/del_host2queues" do |env|
    env.sched.del_host2queues
  end

  # client(runner) report job's status
  # /~lkp/cgi-bin/lkp-jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
  get "/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
    env.sched.update_job_parameter

    "Done"
  end

  # node in cluster requests cluster state
  # wget 'http://localhost:3000/~lkp/cgi-bin/lkp-cluster-sync?job_id=<job_id>&state=<state>'
  # 1) state   : "wait_ready"
  #    response: return "abort" if one node state is "abort",
  #              "ready" if all nodes are "ready", "retry" otherwise.
  # 2) state   : wait_finish
  #    response: return "abort" if one node state is "abort",
  #              "finish" if all nodes are "finish", "retry" otherwise.
  # 3) state   : abort | failed
  #    response: update the node state to "abort",
  #              return all nodes states at this moment.
  # 4) state   : write_state
  #    response: add "roles" and "ip" fields to cluster state,
  #              return all nodes states at this moment.
  # 5) state   : roles_ip
  #    response: get "server ip" from cluster state,
  #              return "server=<server ip>".
  get "/~lkp/cgi-bin/lkp-cluster-sync" do |env|
    env.sched.request_cluster_state
  end

  # client(runner) report job post_run finished
  # /~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  get "/~lkp/cgi-bin/lkp-post-run" do |env|
    env.sched.close_job.to_json
  end

  get "/~lkp/cgi-bin/lkp-wtmp" do |env|
    env.sched.update_tbox_wtmp

    "Done"
  end

  get "/~lkp/cgi-bin/report_ssh_port" do |env|
    env.sched.report_ssh_port

    "Done"
  end

  # content='{"tbox_name": "'$HOSTNAME'", "job_id": "'$id'", "ssh_port": "'$ssh_port'", "message": "'$message'"}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/~lkp/cgi-bin/report_ssh_info" -d "$content"
  post "/~lkp/cgi-bin/report_ssh_info" do |env|
    env.sched.report_ssh_info

    "Done"
  end

  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/rpmbuild/submit_reverse_depend_jobs" -d "$content"
  post "/rpmbuild/submit_reverse_depend_jobs" do |env|
    env.sched.submit_reverse_depend_jobs
  end
end
