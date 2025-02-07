# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/sched"
require "../lib/json_logger"
require "../lib/host"

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
# - restful API [get "/job_initrd_tmpfs/11/job.cgz"] to download job(11) job.cgz file
# - restful API [get "/scheduler/lkp/jobfile-append-var"] report job var that should be append
# - restful API [get "/scheduler/lkp/cluster-sync"] for nodes to request cluster state
# - restful API [get "/scheduler/lkp/post-run" ] to move job from redis queue "sched/jobs_running" to "sched/extract_stats" and remove job from redis queue "sched/id2job"
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
    env.set "api", Sched.instance.get_api(env).to_s
  rescue e
    env.log.warn(e.inspect_with_backtrace)
  end

  after_all do |env|
    env.log.info({
      "from" => env.request.remote_address.to_s,
      "message" => "access_record"
    }.to_json) if env.response.status_code == 200

    GC.collect
  rescue e
    env.log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end

  # ----------------------------------------
  # old scheduler api
  # ----------------------------------------

  # echo alive
  get "/" do |env|
    Sched.instance.alive(VERSION)
  end

  post "/register-host" do |env|
    host_info = JSON.parse(env.request.body.not_nil!.gets_to_end).as_h

    Sched.instance.register_host(host_info)
  end

  # for XXX_runner get job
  #
  # /boot.ipxe/mac/${mac}
  # /boot.xxx/host/${hostname}
  # /boot.yyy/mac/${mac}
  get "/boot.:boot_type/:parameter/:value" do |env|
    Sched.instance.hw_find_job_boot(env)
  end

  get "/heart-beat" do |env|
    status = Sched.instance.heart_beat(env)
    {"status_code" => status}.to_json
  rescue e
    env.log.warn({
      "message" => e.to_s,
      "error_message" => e.inspect_with_backtrace.to_s
    }.to_json)
  end


  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  post "/submit_job" do |env|
    Sched.instance.submit_job(env).to_json
  end

  # delete jobs from queue
  post "/cancel_jobs" do |env|
    Sched.instance.cancel_jobs(env).to_json
  end

  post "/scheduler/update-subqueues" do |env|
    Sched.instance.update_subqueues(env).to_json
  end

  post "/scheduler/delete-subqueue" do |env|
    Sched.instance.delete_subqueue(env).to_json
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'
  post "/report_event" do |env|
    Sched.instance.report_event(env).to_s
  end

  # extend the deadline
  # curl "http://localhost:3000/renew_deadline?job_id=1&time=100
  get "/renew_deadline" do |env|
    Sched.instance.renew_deadline(env).to_s
  end

  # get testbox deadline
  # curl "http://localhost:3000/get_deadline?testbox=xxx
  get "/get_deadline" do |env|
    Sched.instance.get_deadline(env).to_s
  end

  # get testbox info
  # curl "http://localhost:3000/get_testbox?testbox=xxx
  get "/get_testbox" do |env|
    Sched.instance.get_testbox(env).to_json
  end

  # file download server
  get "/job_initrd_tmpfs/:job_id/:job_package" do |env|
    Sched.instance.download_file(env)
  end

  # client(runner) report job's status
  # /~lkp/cgi-bin/lkp-jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
  get "/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
    Sched.instance.update_job_parameter(env)

    "Done"
  end

  # client(runner) report job's step
  # /~lkp/cgi-bin/report-job-step
  #  ?job_step=smoke_basic_os&job_id=10
  #  ?job_step=smoke_baseinfo&job_id=10
  #  ?job_step=smoke_docker&job_id=10
  get "/~lkp/cgi-bin/report-job-step" do |env|
    Sched.instance.report_job_step(env)

    "Done"
  end

  # client(runner) report job's stage
  # /~lkp/cgi-bin/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  get "/~lkp/cgi-bin/set-job-stage" do |env|
    Sched.instance.set_job_stage(env)

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
    Sched.instance.request_cluster_state(env)
  end

  # client(runner) report job post_run finished
  # /~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  get "/~lkp/cgi-bin/lkp-post-run" do |env|
    Sched.instance.close_job(env).to_json
  end

  get "/~lkp/cgi-bin/lkp-wtmp" do |env|
    # obsolete API

    "Done"
  end

  get "/~lkp/cgi-bin/report_ssh_port" do |env|
    Sched.instance.report_ssh_port(env)

    "Done"
  end

  # content='{"tbox_name": "'$HOSTNAME'", "job_id": "'$id'", "ssh_port": "'$ssh_port'", "message": "'$message'"}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/~lkp/cgi-bin/report_ssh_info" -d "$content"
  post "/~lkp/cgi-bin/report_ssh_info" do |env|
    Sched.instance.report_ssh_info(env)

    "Done"
  end

  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/rpmbuild/submit_reverse_depend_jobs" -d "$content"
  post "/rpmbuild/submit_reverse_depend_jobs" do |env|
    Sched.instance.submit_reverse_depend_jobs(env)
  end

  post "/rpmbuild/submit_install_rpm" do |env|
    Sched.instance.submit_install_rpm(env)
  end

  # content='{"type": "create", "job_id": "1", "srpms": [{"os":"centos7", "srpm":"test", "repo_name": "base"}]}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/repo/set-srpm-info" -d "$content"
  post "/repo/set-srpm-info" do |env|
    Sched.instance.set_srpm_info(env)
  end

  # -----------------------------------------
  # new sched api
  # -----------------------------------------

  # echo alive
  get "/scheduler/" do |env|
    Sched.instance.alive(VERSION)
  end

  ws "/scheduler/ws/boot.:boot_type/:parameter/:value" do |socket, env|
    env.set "ws", true
    env.set "ws_state", "normal"
    sched = Sched.instance

    spawn sched.find_job_boot(env, socket)

    socket.on_message do |msg|
      msg = JSON.parse(msg.to_s).as_h?
      (spawn env.channel.send(msg)) if msg
    end

    socket.on_close do
      env.set "ws_state", "close"
      env.log.info({
        "from" => env.request.remote_address.to_s,
        "message" => "socket on closed"
      }.to_json)
    end
  end

  # Handle connections from MultiQEMUDocker instances
  # Each host machine can run only one single MultiQEMUDocker instance
  ws "/scheduler/vm-container-provider/:host" do |socket, env|
    sched = Sched.instance
    sched.handle_provider_websocket(socket, env)
  end

  # Client connection handler
  ws "/scheduler/client" do |socket, env|
    sched = Sched.instance
    sched.handle_client_websocket(socket, env)
  end

  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  post "/scheduler/submit-job" do |env|
    Sched.instance.submit_job(env).to_json
  end

  # delete jobs from queue
  post "/scheduler/cancel-jobs" do |env|
    Sched.instance.cancel_jobs(env).to_json
  end

  # force stop a running job, reboot/reclaim the hw/vm/container machine running the job immediately
  get "/scheduler/stop-job/:job_id" do |env|
    job_id = env.params.url["job_id"].to_i64
    Sched.instance.stop_job(job_id)
  end

  # wait until any job field value meets the expected value
  # return the remaining unmet job fields
  # use post instead of ws to enable shell wget/curl clients
  post "/scheduler/wait-jobs" do |env|
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/scheduler/report_event -d '#{data.to_json}'
  post "/scheduler/report-event" do |env|
    Sched.instance.report_event(env).to_s
  end

  # extend the deadline
  # curl "http://localhost:3000/scheduler/renew_deadline?job_id=1&time=100
  get "/scheduler/renew-deadline" do |env|
    Sched.instance.renew_deadline(env).to_s
  end

  # get testbox deadline
  # curl "http://localhost:3000/scheduler/get_deadline?testbox=xxx
  get "/scheduler/get-deadline" do |env|
    Sched.instance.get_deadline(env).to_s
  end

  # get testbox info
  # curl "http://localhost:3000/scheduler/get_testbox?testbox=xxx
  get "/scheduler/get-testbox" do |env|
    Sched.instance.get_testbox(env).to_json
  end

  # file download server
  get "/scheduler/job-initrd-tmpfs/:job_id/:job_package" do |env|
    Sched.instance.download_file(env)
  end

  # client(runner) report job's status
  # /scheduler/lkp/jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
  get "/scheduler/lkp/jobfile-append-var" do |env|
    Sched.instance.update_job_parameter(env)

    "Done"
  end

  # client(runner) report job's stage
  # /scheduler/lkp/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  get "/scheduler/lkp/set-job-stage" do |env|
    Sched.instance.set_job_stage(env)

    "Done"
  end

  # node in cluster requests cluster state
  # wget 'http://localhost:3000/scheduler/lkp/cluster-sync?job_id=<job_id>&state=<state>'
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
  get "/scheduler/lkp/cluster-sync" do |env|
    Sched.instance.request_cluster_state(env)
  end

  # client(runner) report job post_run finished
  # /scheduler/lkp/post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  get "/scheduler/lkp/post-run" do |env|
    Sched.instance.close_job(env).to_json
  end

  get "/scheduler/lkp/report-ssh-port" do |env|
    Sched.instance.report_ssh_port(env)

    "Done"
  end

  # content='{"tbox_name": "'$HOSTNAME'", "job_id": "'$id'", "ssh_port": "'$ssh_port'", "message": "'$message'"}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/lkp/report_ssh_info" -d "$content"
  post "/scheduler/lkp/report-ssh-info" do |env|
    Sched.instance.report_ssh_info(env)

    "Done"
  end

  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/rpmbuild/submit_reverse_depend_jobs" -d "$content"
  post "/scheduler/rpmbuild/submit-reverse-depend-jobs" do |env|
    Sched.instance.submit_reverse_depend_jobs(env)
  end

  post "/scheduler/rpmbuild/submit-install-rpm" do |env|
    Sched.instance.submit_install_rpm(env)
  end

  # content='{"type": "create", "job_id": "1", "srpms": [{"os":"centos7", "srpm":"test", "repo_name": "base"}]}'
  # curl -XPOST "http://$LKP_SERVER:${LKP_CGI_PORT:-3000}/scheduler/repo/set-srpm-info" -d "$content"
  post "/scheduler/repo/set-srpm-info" do |env|
    Sched.instance.set_srpm_info(env)
  end

end
