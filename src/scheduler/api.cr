# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "../lib/web_env"
require "../lib/sched"
require "../lib/json_logger"
require "../lib/host"
require "../lib/account"

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
# - restful API [get "/scheduler/job/update"] report job var that should be append
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

  # for XXX_runner get job
  #
  # /boot.ipxe/mac/${mac}
  # /boot.xxx/host/${hostname}
  # /boot.yyy/mac/${mac}
  get "/boot.:boot_type/:parameter/:value" do |env|
    Sched.instance.api_hw_find_job_boot(env)
  end

  get "/scheduler/job/request" do |env|
    Sched.instance.api_hw_find_job_boot(env)
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
    Sched.instance.api_submit_job(env).to_json
  end

  # delete jobs from queue
  post "/cancel_jobs" do |env|
    Sched.instance.cancel_jobs(env).to_json
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'
  post "/report_event" do |env|
    Sched.instance.report_event(env).to_s
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
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job's step
  # /~lkp/cgi-bin/report-job-step
  #  ?job_step=smoke_basic_os&job_id=10
  #  ?job_step=smoke_baseinfo&job_id=10
  #  ?job_step=smoke_docker&job_id=10
  get "/~lkp/cgi-bin/report-job-step" do |env|
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job's stage
  # /~lkp/cgi-bin/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  get "/~lkp/cgi-bin/set-job-stage" do |env|
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job post_run finished
  # /~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  get "/~lkp/cgi-bin/lkp-post-run" do |env|
    # obsolete API
    # job will be closed when client setting job_stage to finish or set_job_state to some error string
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

  # Handle connections from MultiQEMUDocker instances
  # Each host machine can run only one single MultiQEMUDocker instance
  ws "/scheduler/vm-container-provider/:host" do |socket, env|
    sched = Sched.instance
    sched.api_provider_websocket(socket, env)
  end

  # Client connection handler
  ws "/scheduler/client" do |socket, env|
    sched = Sched.instance
    sched.api_client_websocket(socket, env)
  end

  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  post "/scheduler/submit-job" do |env|
    Sched.instance.api_submit_job(env).to_json
  end

  # delete jobs from queue
  post "/scheduler/cancel-jobs" do |env|
    Sched.instance.cancel_jobs(env).to_json
  end

  # force stop a running job, reboot/reclaim the hw/vm/container machine running the job immediately
  get "/scheduler/terminate-job/:job_id" do |env|
    job_id = env.params.url["job_id"].to_i64
    Sched.instance.api_terminate_job(job_id)
  end

  # wait until any job meets the expected field values
  # return the remaining unmet jobs/fields
  # use post instead of ws to enable shell wget/curl clients
  post "/scheduler/wait-jobs" do |env|
    env.response.content_type = "application/json"
    Sched.instance.api_wait_jobs(env).to_s
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/scheduler/report_event -d '#{data.to_json}'
  post "/scheduler/report-event" do |env|
    Sched.instance.report_event(env).to_s
  end

  # get host machine info
  # curl "http://localhost:3000/scheduler/host?hostname=xxx
  get "/scheduler/host" do |env|
    env.response.content_type = "application/json"
    hostname = env.params.query["hostname"].to_s
    Sched.instance.api_get_host(hostname).to_json
  end

  # register host machine
  post "/scheduler/host" do |env|
    host_info = JSON.parse(env.request.body.not_nil!.gets_to_end).as_h

    Sched.instance.api_register_host(host_info)
  end

  # file download server
  get "/scheduler/job-initrd-tmpfs/:job_id/:job_package" do |env|
    Sched.instance.download_file(env)
  end

  # client(runner) report job's status
  # /scheduler/lkp/jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  get "/scheduler/job/update" do |env|
    Sched.instance.api_update_job(env)
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
