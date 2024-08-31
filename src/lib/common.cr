require "../scheduler/elasticsearch_client"

class Common
  # If you do not restart the system to consume the next job,
  # check whether the system of the job to be consumed is consistent with that of the previous job
  def self.match_no_reboot?(etcd_job, pre_job, es : Elasticsearch::Client)
    return true unless pre_job

    job_id = etcd_job.key.split("/")[-1]
    job = es.get_job(job_id.to_s)

    determine_parameters = [
      "os",
      "os_version",
      "os_aarch",
      "os_mount",
      "kernel_uri",
      "modules_uri",
      "do_not_reboot"
    ]

    return false unless job

    determine_parameters.each do |k|
      return false unless job[k] == pre_job[k]
    end

    return true
  end

  def self.split_jobs_by_subqueue(jobs)
    hash = Hash(String, Array(Etcd::Model::Kv)).new
    jobs.each do |job|
      key = job.key.split("/")[5]
      if hash.has_key?(key)
        hash[key] << job
      else
        hash[key] = [job]
      end
    end

    return hash
  end

  def self.download_file(url, output, rpms_dir)
    lockfile = "#{output}.lock"

    while true
      result = Process.run("mkdir", args: ["#{lockfile}"])
      if result.exit_code != 0
        sleep 3
      else
        break
      end
    end

    result = Process.run("sh", args: ["-c","cd #{rpms_dir} && wget --timestamping --tries=3 #{url}"])
    FileUtils.rm_rf(lockfile)

    return result.exit_code
  end
end
