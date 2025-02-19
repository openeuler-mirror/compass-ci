# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

class Sched
  def api_download_job_file(env)
    job_id = env.params.url["job_id"]
    job_package = env.params.url["job_package"]
    file_path = ::File.join [Kemal.config.public_folder, job_id, job_package]

    env.set "job_id", job_id
    env.set "job_state", "download"

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
    requested_path = Path[requested_path].expand

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
      env.response.status_code = 404
      return "File not found"
    end

    # Serve the file
    send_file env, full_path
  end

end
