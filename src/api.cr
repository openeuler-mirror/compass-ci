# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "kemal"

require "./lib/web_env"
require "./lib/json_logger"
require "./sched"
require "./host"
require "./account"

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

# Struct to represent a result with success/failure status
struct Result
  getter success : Bool
  getter message : String
  getter status_code : HTTP::Status

  def self.success(message : String) : Result
    new(true, message, HTTP::Status::OK)
  end

  def self.error(status_code : HTTP::Status, message : String) : Result
    new(false, message, status_code)
  end

  private def initialize(@success, @message, @status_code)
  end
end

module Kemal
  # Custom LogHandler that outputs local time instead of UTC
  class LocalTimeLogHandler < Kemal::BaseLogHandler
    def initialize(@io : IO = STDOUT)
    end

    def call(context : HTTP::Server::Context)
      # Measure the elapsed time for the request
      elapsed_time = Time.measure { call_next(context) }
      elapsed_text = elapsed_text(elapsed_time)

      # Output the log with local time
      @io << Time.local << ' ' <<
      context.response.status_code << ' ' <<
      context.request.method << ' ' <<
      context.request.resource << ' ' <<
      elapsed_text << '\n'
      @io.flush
      context
    end

    def write(message : String)
      @io << message
      @io.flush
      @io
    end

    private def elapsed_text(elapsed)
      millis = elapsed.total_milliseconds
      return "#{millis.round(2)}ms" if millis >= 1

      "#{(millis * 1000).round(2)}µs"
    end
  end
end

# Replace the default logger with the custom LocalTimeLogHandler
logger Kemal::LocalTimeLogHandler.new

module Scheduler

  # Dynamically generate the VERSION constant based on the last commit's date and short hash
  GIT_COMMIT_DATE = `git log -1 --date=format:'%Y%m%d' --pretty=format:%cd`.strip
  GIT_SHORT_HASH  = `git log -1 --pretty=format:%h`.strip

  # Fallback in case Git commands fail (e.g., not in a Git repository)
  VERSION = if GIT_COMMIT_DATE.empty? || GIT_SHORT_HASH.empty?
              # Use today's date in the format YYYYMMDD if Git information is unavailable
              `date +%Y%m%d`.chomp
            else
              # Combine the commit date and short hash with a dot separator
              "#{GIT_COMMIT_DATE}.#{GIT_SHORT_HASH}"
            end

  logging true

  add_context_storage_type(Time::Span)

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

  # enqueue
  #  - echo job_id to caller
  #  -- job_id = "0" ? means failed
  # XXX: obsolete
  post "/submit_job" do |env|
    env.response.content_type = "application/json"

    # Parse request body as JSON
    job_content = begin
                    JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
                  rescue JSON::ParseException
                    env.response.status_code = HTTP::Status::BAD_REQUEST.code
                    next {"message" => "Invalid JSON in request body"}.to_json
                  end

    # Verify account authentication
    result = Sched.instance.accounts_cache.verify_account(job_content)
    unless result.success
      env.response.status_code = result.status_code.code
      next result.message
    end

    result = Sched.instance.api_submit_job(job_content)
    env.response.status_code = result.status_code.code
    result.message
  end

  # for client to report event
  # this event is recorded in the log
  # curl -H 'Content-Type: application/json' -X POST #{SCHED_HOST}:#{SCHED_PORT}/report_event -d '#{data.to_json}'
  post "/report_event" do |env|
    Sched.instance.report_event(env).to_s
  end

  # file download server
  # XXX: obsolete
  get "/job_initrd_tmpfs/:job_id/:job_package" do |env|
    Sched.instance.api_download_job_file(env)
  end

  get "/srv/*path" do |env|
    Sched.instance.api_download_srv_file(env)
  end

  post "/result/*path" do |env|
    code, text = Sched.instance.api_upload_result(env, false)
    env.response.status_code = code
    text
  end

  post "/srv/*path" do |env|
    code, text = Sched.instance.api_upload_result(env, true)
    env.response.status_code = code
    text
  end

  # client(runner) report job's status
  # /~lkp/cgi-bin/lkp-jobfile-append-var
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=running&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&job_state=post_run&job_id=10
  #  ?job_file=/lkp/scheduled/job.yaml&loadavg=0.28 0.82 0.49 1/105 3389&start_time=1587725398&end_time=1587725698&job_id=10
  # XXX: obsolete
  get "/~lkp/cgi-bin/lkp-jobfile-append-var" do |env|
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job's step
  # /~lkp/cgi-bin/report-job-step
  #  ?job_step=smoke_basic_os&job_id=10
  #  ?job_step=smoke_baseinfo&job_id=10
  #  ?job_step=smoke_docker&job_id=10
  # XXX: obsolete
  get "/~lkp/cgi-bin/report-job-step" do |env|
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job's stage
  # /~lkp/cgi-bin/set-job-stage
  #   ?job_stage=on_fail&job_id=10
  #   ?job_stage=on_fail&job_id=10&timeout=21400
  # XXX: obsolete
  get "/~lkp/cgi-bin/set-job-stage" do |env|
    Sched.instance.api_update_job(env)
  end

  # client(runner) report job post_run finished
  # /~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40
  #  curl "http://localhost:3000/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"
  # XXX: obsolete
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

  # Health check endpoint
  get "/scheduler/v1/health" do |env|
    env.response.content_type = "text/plain"
    Sched.instance.alive(VERSION)
  end

  # WebSocket endpoints

  ws "/scheduler/v1/client" do |socket, env|
    sched = Sched.instance
    sched.api_client_websocket(socket, env)
  end

  ws "/scheduler/v1/vm-container-provider/:host" do |socket, env|
    sched = Sched.instance
    sched.api_provider_websocket(socket, env)
  end

  # Job-related endpoints

  post "/scheduler/v1/jobs/submit" do |env|
    env.response.content_type = "application/json"

    # Parse request body as JSON
    job_content = begin
                    JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
                  rescue JSON::ParseException
                    env.response.status_code = HTTP::Status::BAD_REQUEST.code
                    next {"message" => "Invalid JSON in request body"}.to_json
                  end

    # Verify account authentication
    result = Sched.instance.accounts_cache.verify_account(job_content)
    unless result.success
      env.response.status_code = result.status_code.code
      next result.message
    end

    result = Sched.instance.api_submit_job(job_content)
    env.response.status_code = result.status_code.code
    result.message
  end

  get "/scheduler/v1/jobs/dispatch" do |env|
    env.response.content_type = "text/plain"
    Sched.instance.api_hw_find_job_boot(env)
  end

  get "/scheduler/v1/jobs/:job_id" do |env|
    job_id = env.params.url["job_id"].to_i64
    fields = env.params.query["fields"]?

    env.response.content_type = "application/json"

    if job = Sched.instance.api_view_job(job_id, fields)
      job
    else
      env.response.status_code = HTTP::Status::NOT_FOUND.code
      {error: "Job not found"}.to_json
    end
  end

  post "/scheduler/v1/jobs/wait" do |env|
    env.response.content_type = "application/json"
    Sched.instance.api_wait_jobs(env).to_json
  end

  # Endpoint to handle job updates via POST (since `busybox wget` only supports GET/POST)
  post "/scheduler/v1/jobs/:job_id/update" do |env|
    env.response.content_type = "text/plain"
    result = Sched.instance.api_update_job(env)
    if result.success
      env.response.status_code = HTTP::Status::OK.code
      result.message
    else
      env.response.status_code = result.status_code.code
      result.message
    end
  end

  # Endpoint to cancel a job via POST
  post "/scheduler/v1/jobs/:job_id/cancel" do |env|
    env.response.content_type = "text/plain"

    # Parse job ID from URL parameters
    job_id = env.params.url["job_id"].to_i64

    # Read and parse the request body
    json = begin
             JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
           rescue JSON::ParseException
             env.response.status_code = HTTP::Status::BAD_REQUEST.code
             next "Invalid JSON in request body"
           end

    # Verify account authentication
    result = Sched.instance.accounts_cache.verify_account(json)
    unless result.success
      env.response.status_code = result.status_code.code
      next result.message
    end

    # Attempt to cancel the job
    status_code, message = Sched.instance.api_cancel_job(job_id)
    env.response.status_code = status_code.code
    message
  end

  post "/scheduler/v1/jobs/:job_id/terminate" do |env|
    # Set the response content type
    env.response.content_type = "text/plain"

    # Extract and validate the job ID from the URL parameters
    job_id_param = env.params.url["job_id"]?
    unless job_id_param && (job_id = job_id_param.to_i64?)
      next HTTP::Status::BAD_REQUEST, "Invalid job ID"
    end

    # Read and parse the request body
    json = begin
             JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
           rescue JSON::ParseException
             env.response.status_code = HTTP::Status::BAD_REQUEST.code
             next "Invalid JSON in request body"
           end

    # Verify account authentication
    result = Sched.instance.accounts_cache.verify_account(json)
    unless result.success
      env.response.status_code = result.status_code.code
      next result.message
    end

    # Call the API to terminate the job
    code, text = Sched.instance.api_terminate_job(job_id)

    env.response.status_code = code.code
    text
  end

  # Host-related endpoints

  get "/scheduler/v1/hosts/:hostname" do |env|
    env.response.content_type = "application/json"

    # Extract hostname from URL parameters
    hostname = env.params.url["hostname"]?

    # Validate hostname
    unless hostname
      env.response.status_code = HTTP::Status::BAD_REQUEST.code
      next { "error" => "Hostname is required" }.to_json
    end

    # Fetch host information
    host_info = Sched.instance.api_get_host(hostname)

    # Handle host not found
    if host_info.nil?
      env.response.status_code = HTTP::Status::NOT_FOUND.code
      next { "error" => "Host not found", "hostname" => hostname }.to_json
    end

    # Return host information
    host_info.to_json
  end

  # Register host
  post "/scheduler/v1/hosts/:hostname" do |env|
    env.response.content_type = "text/plain"

    # Extract hostname from URL parameters
    hostname = env.params.url["hostname"]?

    # Validate hostname
    unless hostname
      env.response.status_code = HTTP::Status::BAD_REQUEST.code
      next "Hostname is required"
    end

    # Parse and validate request body
    host_hash = begin
                  JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
                rescue JSON::ParseException
                  env.response.status_code = HTTP::Status::BAD_REQUEST.code
                  next "Invalid JSON in request body"
                end

    # Check if the hostname in the body matches the URL parameter
    unless host_hash["hostname"]? == hostname
      env.response.status_code = HTTP::Status::BAD_REQUEST.code
      next "Hostname in body does not match URL parameter"
    end

    # Register or update host information
    for_metrics = env.params.query.has_key?("report_metrics")
    result = Sched.instance.api_register_host(hostname, host_hash, for_metrics)
    env.response.status_code = result.status_code.code
    result.message
  end

  # Account-related endpoints

  post "/scheduler/v1/accounts/:my_account" do |env|
    env.response.content_type = "application/json"

    # Extract account name from URL parameters
    account_name = env.params.url["my_account"]?

    # Validate account name
    unless account_name
      env.response.status_code = HTTP::Status::BAD_REQUEST.code
      next { "error" => "Account name is required" }.to_json
    end

    # Check if the client is local
    unless Sched.instance.detect_local_client(env)
      env.response.status_code = HTTP::Status::FORBIDDEN.code
      next { "error" => "Access denied: Only local clients are allowed" }.to_json
    end

    # Parse and validate request body
    account_hash = begin
                     JSON.parse(env.request.body.not_nil!.gets_to_end).as_h
                   rescue JSON::ParseException
                     env.response.status_code = HTTP::Status::BAD_REQUEST.code
                     next { "error" => "Invalid JSON in request body" }.to_json
                   end

    # Validate admin token
    admin_token = account_hash.delete("admin_token")
    unless admin_token && admin_token.as_s == Sched.options.admin_token
      env.response.status_code = HTTP::Status::UNAUTHORIZED.code
      next { "error" => "Invalid or missing admin token" }.to_json
    end

    # Register account
    result = Sched.instance.api_register_account(account_name, account_hash)
    env.response.status_code = result.status_code.code
    result.message

    # Handle registration result
    if result.success
      { "status" => "success", "account_name" => account_name }.to_json
    else
      { "error" => result.message, "account_name" => account_name }.to_json
    end
  end

  # Dashboard endpoints

  get "/scheduler/v1/dashboard/jobs/pending" do |env|
    Sched.instance.api_dashboard_jobs(env)
  end

  get "/scheduler/v1/dashboard/jobs/running" do |env|
    Sched.instance.api_dashboard_jobs(env)
  end

  get "/scheduler/v1/dashboard/hosts" do |env|
    Sched.instance.api_dashboard_hosts(env)
  end

  get "/scheduler/v1/dashboard/accounts" do |env|
    Sched.instance.api_dashboard_accounts(env)
  end

  # Debug endpoints

  get "/scheduler/v1/debug/dispatch" do |env|
    Sched.instance.api_debug_dispatch(env)
  end

end
