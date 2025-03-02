# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_download_job_file(env)
    job_id = env.params.url["job_id"]
    job_package = env.params.url["job_package"]
    file_path = ::File.join [Kemal.config.public_folder, job_id, job_package]

    send_file env, file_path

    # delete the folder after the download is complete
    FileUtils.rm_rf(::File.join [Kemal.config.public_folder, job_id])
  rescue e
    env.response.status_code = 500
    @log.warn(e)
  end

  # Helper method to sanitize and validate file paths
  def valid_file_path(requested_path : String | Nil) : String | Nil
    return nil unless requested_path
    return nil if requested_path.to_s.includes?("/../")

    # Ensure the requested path starts with BASE_DIR/scheduler and does not contain any '..' sequences
    # base_dir = Path[BASE_DIR] / "scheduler"
    # requested_path = Path[requested_path].expand

    # return nil unless requested_path.starts_with?("#{BASE_DIR}/scheduler")

    full_path = File.join(BASE_DIR, requested_path)
    return full_path
  end

  def api_download_srv_file(env)
    # job_id = env.params.query["job_id"]?
    # job_token = env.params.query["job_token"]?

    # # Validate required parameters
    # if job_id.nil? || job_token.nil?
    #   env.response.status_code = 400
    #   return "Missing job_id or job_token"
    # end

    # job = get_job(job_id.to_i64)
    # if job.nil? || job[:token] != job_token
    #   env.response.status_code = 401
    #   return "Invalid job credentials"
    # end

    # Validate and sanitize file path
    requested_path = env.params.url["path"]?
    full_path = valid_file_path(requested_path)

    # Prevent directory traversal
    unless full_path
      env.response.status_code = 403
      return "Invalid file path"
    end

    # Check if file is in allowed list
    # allowed_paths = job[:initrd_uris].map { |uri| URI.parse(uri).path }
    # unless allowed_paths.includes?(full_path)
    #   env.response.status_code = 403
    #   return "File not authorized for this job"
    # end

    # Verify file exists
    unless File.exists?(full_path) && File.file?(full_path)
      @log.error "File not found: #{full_path}"
      env.response.status_code = 404
      return "File not found"
    end

    check_set_boot_stage(requested_path)

    # Serve the file
    send_file env, full_path
  end

  def check_set_boot_stage(requested_path)
    return unless requested_path =~ /scheduler\/pending-jobs\/(\d+)\/job.cgz$/

    id = $1
    job = get_job(id.to_i64)
    return unless job

    # downloading job.cgz auto marks going into boot stage
    change_job_stage(job, "boot", nil)
  end

  # job_token is created on dispatched jobs.
  # It won't be stored to ES.
  # If scheduler crash, it can reloaded from job_dir's job.yaml
  def api_upload_result(env, to_upload_dirs)
    # Extract query parameters
    job_id = env.params.query["job_id"]?
    job_token = env.params.query["job_token"]?

    # Validate job_id and job_token
    unless job_id && job_token
      return 401, "Unauthorized - no job params"
    end

    job = get_job(job_id.to_i64)
    unless job
      return 401, "Unauthorized - no job"
    end
    # unless job.has_key?("job_token") && job["job_token"] == job_token
    #   return 401, "Unauthorized - job token mismatch"
    # end

    # Validate job stage
    if job.hash_int32.has_key? "idata_readiness" &&
       job.idata_readiness >= JOB_DATA_READINESS_NAME2ID["uploaded"]
      return 423, "Job data already uploaded"
    end

    if job.istage < JOB_STAGE_NAME2ID["dispatch"]
      return 403, "Job not running"
    end

    # Extract and validate path parameter
    requested_path = env.params.url["path"]?
    unless requested_path
      return 402, "Empty path"
    end

    if requested_path.includes?("/../")
        return 406, "Illegal path"
    end

    if to_upload_dirs
      # Check if requested_path starts with any directory in job.upload_dirs
      requested_path = "/" + requested_path
      unless job.upload_dirs.split(",").any? { |dir| requested_path.starts_with?(dir) }
        return 403, "Forbidden path"
      end
    else
      requested_path = "/result/" + requested_path
      unless requested_path.starts_with?(job.result_root)
        return 403, "Forbidden path"
      end
    end

    # Ensure target directory exists
    full_path = "#{BASE_DIR}#{requested_path}"
    FileUtils.mkdir_p(File.dirname(full_path))

    # Check if file already exists
    if File.exists?(full_path)
      return 409, "File already exists"
    end

    # Save uploaded file to a temporary location first
    temp_file = "#{full_path}.tmp"
    unless body = env.request.body
      return 400, "Empty body"
    end

    begin
      File.open(temp_file, "w") do |f|
        IO.copy(body, f)
      end

      # Move temp file to final destination
      FileUtils.mv(temp_file, full_path)
    end

    return 200, "File uploaded successfully"
  end

end
