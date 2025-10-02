
# jobinfo yaml format
# $JOBS_DIR/$job_id.yaml
#   id: job_id
#   tbox_type: qemu|container
#   hostname: vm-1 | dc-3
#   fork_pid: 123
#
# job <> container mapping
#   docker run --name=$hostname
#   docker rm -f $hostname
#   container_id=$(docker container ls -q --filter name=$hostname)
#
# job <> qemu mapping
#   qemu --pid-file $PIDS_DIR/$hostname
#   kill $(<$PIDS_DIR/$hostname)

require 'concurrent'

class JobTracker
  attr_reader :jobs

  @@nr_vm = 0
  @@nr_container = 0

  def self.nr_vm
    @@nr_vm
  end

  def self.nr_container
    @@nr_container
  end

  def initialize
    @jobs = Concurrent::Hash.new
    load_jobs
  end

  def load_jobs
    Dir[File.join(ENV["JOBS_DIR"], '*.yaml')].each do |file|
      job_data = YAML.safe_load(File.read(file))
      job_data.transform_keys(&:to_sym)

      # Check if the process with fork_pid exists
      if job_data[:fork_pid] && !Dir.exist?("/proc/#{job_data[:fork_pid]}")
        # If the process does not exist, remove the file and skip to the next iteration
        puts "removing stale job info #{file}"
        File.delete(file)
        next
      end

      @jobs[job_data[:id]] = job_data
      if job_data[:tbox_type] == "vm"
        @@nr_vm += 1
      else
        @@nr_container += 1
      end
    end
  end

  def [](job_id)
    @jobs[job_id]
  end

  def add_job(job_data)
    job_id = job_data[:id]
    @jobs[job_data[:id]] = job_data
    create_job_file(job_id, job_data)
    if job_data[:tbox_type] == "vm"
      @@nr_vm += 1
    else
      @@nr_container += 1
    end
  end

  def remove_job(job_id)
    job_data = @jobs.delete job_id
    return nil unless job_data
    FileUtils.rm(job_file_path(job_id))
    if job_data[:tbox_type] == "vm"
      @@nr_vm -= 1
    else
      @@nr_container -= 1
    end
    job_data
  end

  def find_hostname(tbox_group)
    1.upto(100000) do |i|
      hostname = tbox_group + "-#{i}"

      next if has_hostname(hostname)
      next if hostname_conflict?(tbox_group, hostname)

      return hostname
    end
    raise "Cannot find non-conflict hostname for #{tbox_group}"
  end

  private

  def hostname_conflict?(tbox_group, hostname)
    if tbox_group.start_with?("dc")
      docker_container_exists?(hostname)
    elsif tbox_group.start_with?("vm")
      vm_pid_file_exists?(hostname)
    else
      false
    end
  end

  def has_hostname(hostname)
    @jobs.any? do |_, v|
      v[:hostname] == hostname
    end
  end

  def docker_container_exists?(hostname)
    exists = system("#{ENV['OCI_RUNTIME']} inspect #{hostname} > /dev/null 2>&1")
    if exists
      puts "WARNING: Docker container #{hostname} already exists"
    end
    exists
  rescue
    false
  end

  def vm_pid_file_exists?(hostname)
    pid_file_path = "#{ENV['PIDS_DIR']}/qemu-#{hostname}.pid"
    exists = File.exist?(pid_file_path)
    if exists
      puts "WARNING: VM PID file #{pid_file_path} already exists"
    end
    exists
  end

  def job_file_path(job_id)
    File.join(ENV["JOBS_DIR"], "#{job_id}.yaml")
  end

  def job_file_exists?(job_id)
    File.exist?(job_file_path(job_id))
  end

  def create_job_file(job_id, job_data)
    File.write(
      job_file_path(job_id),
      job_data.transform_keys(&:to_s).to_yaml
    )
  end

  def load_job_from_disk(job_id)
    return nil unless job_file_exists?(job_id)
    job_data = YAML.safe_load(File.read(job_file_path(job_id)))
    job_data.transform_keys(&:to_sym)
  end

end

