
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

class JobTracker
  @jobs = {}
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
    load_jobs
  end

  def load_jobs
    Dir[File.join(ENV["JOBS_DIR"], '*.yaml')].each do |file|
      job_data = YAML.safe_load(File.read(file))
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
    @jobs.delete job_id
    FileUtils.rm(job_file_path(job_id))
    if job_data[:tbox_type] == "vm"
      @@nr_vm += 1
    else
      @@nr_container += 1
    end
  end

  def terminate_job(job_id)
    job = @jobs[job_id]
    case job[:tbox_type]
    when "qemu"
      terminate_qemu(job)
    when "container"
      terminate_container(job)
    end
    Process.kill(0, job[:fork_pid])
    remove_job(job_id)
  end

  def find_hostname(tbox_group)
    1.upto(100000) do |i|
      hostname = tbox_group + "-#{i}"
      return hostname unless has_hostname(hostname)
    end
    raise "Cannot find non-conflict hostname for #{tbox_group}"
  end

  private

  def has_hostname(hostname)
    @jobs.any? do |_, v|
      v[:hostname] == hostname
    end
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
      job_data.to_yaml
    )
  end

  def load_job_from_disk(job_id)
    YAML.safe_load(File.read(job_file_path(job_id))) if job_file_exists?(job_id)
  end

  def terminate_qemu(job)
    qemu_pidfile = "#{PIDS_DIR}/qemu-${job[:hostname].pid}"
    qemu_pid = File.read(qemu_pidfile)
    Process.kill("INT", qemu_pid)
  end

  def terminate_container(job)
    system("docker rm -f #{job[:hostname]}")
  end

end

