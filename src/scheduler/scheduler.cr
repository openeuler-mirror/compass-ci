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

    if env.get?("ws")
      env.log.info({
      "from" => env.request.remote_address.to_s,
      "message" => env.socket.closed?
      }.to_json)
      env.socket.close
      env.log.info({
      "message" => env.socket.closed?
      }.to_json)
    end
    GC.collect
  rescue e
    env.log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  # ----------------------------------------
  # old scheduler api
  # will remove all of them after 2022-4-7
  # ----------------------------------------

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
    env.set "ws_state", "normal"
    env.create_socket(socket)
    sched = env.sched

    spawn sched.find_job_boot

    socket.on_message do |msg|
      msg = JSON.parse(msg.to_s).as_h?
      (spawn env.channel.send(msg)) if msg
    end

    socket.on_close do
      env.set "ws_state", "close"
      sched.etcd_close
      spawn env.watch_channel.send("close") if env.get?("watch_state") == "watching"
      env.log.info({
        "from" => env.request.remote_address.to_s,
        "message" => "socket on closed"
      }.to_json)
    end
  end


  # curl -X PUT "http://localhost:3000/register-host2redis?type=dc&arch=aarch64&...."
  put "/register-host2redis" do |env|
    env.sched.register_host2redis
  end

  get "/heart-beat" do |env|
    status = env.sched.heart_beat
    {"status_code" => status}.to_json
  rescue e
    env.log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end


  ws "/ws/boot.:boot_type" do |socket, env|
    env.set "ws", true
    env.set "ws_state", "normal"
    env.create_socket(socket)
    sched = env.sched

    spawn sched.get_job_boot_content

    socket.on_message do |msg|
      msg = JSON.parse(msg.to_s).as_h?
      (spawn env.channel.send(msg)) if msg
    end

    socket.on_close do
      env.set "ws_state", "close"
      sched.etcd_close
      env.log.info({
        "from" => env.request.remote_address.to_s,
        "message" => "socket on closed"
      }.to_json)
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

  post "/scheduler/update_subqueues" do |env|
    env.sched.update_subqueues.to_json
  end

  post "/scheduler/update_subqueues" do |env|
    env.sched.update_subqueues.to_json
  end

  post "/scheduler/delete_subqueue" do |env|
    env.sched.delete_subqueue.to_json
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

  # client(runner) report job's step
  # /~lkp/cgi-bin/report-job-step
  #  ?job_step=smoke_basic_os&job_id=10
  #  ?job_step=smoke_baseinfo&job_id=10
  #  ?job_step=smoke_docker&job_id=10
  get "/~lkp/cgi-bin/report-job-step" do |env|
    env.sched.report_job_step

    "Done"
  end

  # client(runner) report job's stage
  # /~lkp/cgi-bin/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  get "/~lkp/cgi-bin/set-job-stage" do |env|
    env.sched.set_job_stage

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

  post "/rpmbuild/submit_install_rpm" do |env|
    env.sched.submit_install_rpm
  end

  # content='{"type": "create", "job_id": "1", "srpms": [{"os":"centos7", "srpm":"test", "repo_name": "base"}]}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/repo/set-srpm-info" -d "$content"
  post "/repo/set-srpm-info" do |env|
    env.sched.set_srpm_info
  end

  # -----------------------------------------
  # new sched api
  # -----------------------------------------

  # echo alive
  get "/scheduler/" do |env|
    env.sched.alive(VERSION)
  end

  # for XXX_runner get job
  #
  # /boot.ipxe/mac/${mac}
  # /boot.xxx/host/${hostname}
  # /boot.yyy/mac/${mac}
  get "/scheduler/boot.:boot_type/:parameter/:value" do |env|
    env.sched.find_job_boot
  end

  ws "/scheduler/ws/boot.:boot_type/:parameter/:value" do |socket, env|
    env.set "ws", true
    env.set "ws_state", "normal"
    env.create_socket(socket)
    sched = env.sched

    spawn sched.find_job_boot

    socket.on_message do |msg|
      msg = JSON.parse(msg.to_s).as_h?
      (spawn env.channel.send(msg)) if msg
    end

    socket.on_close do
      env.set "ws_state", "close"
      sched.etcd_close
      spawn env.watch_channel.send("close") if env.get?("watch_state") == "watching"
      env.log.info({
        "from" => env.request.remote_address.to_s,
        "message" => "socket on closed"
      }.to_json)
    end
  end

  # /scheduler/~lkp/cgi-bin/gpxelinux.cgi?hostname=:hostname&mac=:mac&last_kernel=:last_kernel
  get "/scheduler/~lkp/cgi-bin/gpxelinux.cgi" do |env|
    env.sched.find_next_job_boot
  end

  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  post "/scheduler/submit_job" do |env|
    env.sched.submit_job.to_json
  end

  # delete jobs from queue
  post "/scheduler/cancel_jobs" do |env|
    env.sched.cancel_jobs.to_json
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/scheduler/report_event -d '#{data.to_json}'
  post "/scheduler/report_event" do |env|
    env.sched.report_event.to_s
  end

  # extend the deadline
  # curl "http://localhost:3000/scheduler/renew_deadline?job_id=1&time=100
  get "/scheduler/renew_deadline" do |env|
    env.sched.renew_deadline.to_s
  end

  # get testbox deadline
  # curl "http://localhost:3000/scheduler/get_deadline?testbox=xxx
  get "/scheduler/get_deadline" do |env|
    env.sched.get_deadline.to_s
  end

  # get testbox info
  # curl "http://localhost:3000/scheduler/get_testbox?testbox=xxx
  get "/scheduler/get_testbox" do |env|
    env.sched.get_testbox.to_json
  end

  # file download server
  get "/scheduler/job_initrd_tmpfs/:job_id/:job_package" do |env|
    env.sched.download_file
  end

  # client(runner) report its hostname and mac
  #  - when a runner pull jobs with it's mac infor, scheduler find out what hostname is it
  # /set_host_mac?hostname=$hostname&mac=$mac (mac like ef-01-02-03-04-05)
  # add a <mac> => <hostname>
  #
  # curl -X PUT "http://localhost:3000/scheduler/set_host_mac?hostname=wfg&mac=00-01-02-03-04-05"
  put "/scheduler/set_host_mac" do |env|
    env.sched.set_host_mac
  end

  # curl -X PUT "http://localhost:3000/scheduler/set_host2queues?queues=vm-2p8g.aarch64&host=vm-2p8g.aarch64"
  put "/scheduler/set_host2queues" do |env|
    env.sched.set_host2queues
  end

  # curl -X PUT "http://localhost:3000/scheduler/del_host_mac?mac=00-01-02-03-04-05"
  put "/scheduler/del_host_mac" do |env|
    env.sched.del_host_mac
  end

  # curl -X PUT "http://localhost:3000/scheduler/del_host2queues?host=vm-2p8g.aarch64"
  put "/scheduler/del_host2queues" do |env|
    env.sched.del_host2queues
  end

  # client(runner) report job's status
  # /scheduler/~lkp/cgi-bin/lkp-jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
  get "/scheduler/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
    env.sched.update_job_parameter

    "Done"
  end

  # client(runner) report job's stage
  # /scheduler/~lkp/cgi-bin/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  get "/scheduler/~lkp/cgi-bin/set-job-stage" do |env|
    env.sched.set_job_stage

    "Done"
  end

  # node in cluster requests cluster state
  # wget 'http://localhost:3000/scheduler/~lkp/cgi-bin/lkp-cluster-sync?job_id=<job_id>&state=<state>'
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
  get "/scheduler/~lkp/cgi-bin/lkp-cluster-sync" do |env|
    env.sched.request_cluster_state
  end

  # client(runner) report job post_run finished
  # /scheduler/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  get "/scheduler/~lkp/cgi-bin/lkp-post-run" do |env|
    env.sched.close_job.to_json
  end

  get "/scheduler/~lkp/cgi-bin/lkp-wtmp" do |env|
    env.sched.update_tbox_wtmp

    "Done"
  end

  get "/scheduler/~lkp/cgi-bin/report_ssh_port" do |env|
    env.sched.report_ssh_port

    "Done"
  end

  # content='{"tbox_name": "'$HOSTNAME'", "job_id": "'$id'", "ssh_port": "'$ssh_port'", "message": "'$message'"}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/~lkp/cgi-bin/report_ssh_info" -d "$content"
  post "/scheduler/~lkp/cgi-bin/report_ssh_info" do |env|
    env.sched.report_ssh_info

    "Done"
  end

  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/rpmbuild/submit_reverse_depend_jobs" -d "$content"
  post "/scheduler/rpmbuild/submit_reverse_depend_jobs" do |env|
    env.sched.submit_reverse_depend_jobs
  end

  post "/scheduler/rpmbuild/submit_install_rpm" do |env|
    env.sched.submit_install_rpm
  end

  # content='{"type": "create", "job_id": "1", "srpms": [{"os":"centos7", "srpm":"test", "repo_name": "base"}]}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/repo/set-srpm-info" -d "$content"
  post "/scheduler/repo/set-srpm-info" do |env|
    env.sched.set_srpm_info
  end
end
