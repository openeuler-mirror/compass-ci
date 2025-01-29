
require "set"

# a host's job request parameters
struct HostRequest
  property arch : String

  # e.g. taishan200-2280-2s64p-256g--a61
  property host_machine : String

  # e.g. vm-2p8g-1 | vm-custom-1
  property hostname : String

  # e.g. vm-2p8g-1.taishan200-2280-2s64p-256g
  property full_hostname : String

  # e.g. vm-2p8g
  property tbox_group : String

  # e.g. hw | vm | dc | vm,dc
  property tbox_type : String

  # [hostname, tbox_group, hw.$arch] for hw
  # vm.$arch | dc.$arch for vm | dc
  property host_keys : Array(String)

  property freemem : UInt32 # unit: MB
  property is_remote : Bool
  property tags : Set(String)

  def initialize(@arch, @host_machine, @hostname, @tbox_type, tags, @freemem, @is_remote)
    @tbox_group = JobHelper.match_tbox_group(@hostname.sub(/-\d+$/, ""))

    if @host_machine == @hostname
      # hw
      @full_hostname = @host_machine
      @host_keys = [ @host_machine, @tbox_group, "hw.#{@arch}" ]
    else
      # refer to doc/job/fields/testbox.md
      # vm_testbox => ${vm_tbox_group}-N.$host_testbox
      @full_hostname = "#{@hostname}.#{@host_machine}"
      @host_keys = [ @host_machine ]
      @tbox_type.split(",") { |t| @host_keys << "#{t}.#{@arch}" }
    end

    @tags = Set(String).new (tags||"").split(",")
  end
end

class Sched

  # Cache for jobs in 'submit' stage
  property jobs_cache_in_submit = Hash(Int64, JobHash).new
  THRESH_JOBS_CACHE_IN_SUBMIT = 6000

  property nr_jobs_by_hostkey = Hash(String, Int32).new { 0 }

  # Reverse index for jobs by user account
  # key1: host_req.host_keys[]
  # key2: job.my_account
  # key3: job.schedule_priority
  property jobid_by_user = Hash(String, Hash(String, Hash(Int8, Set(Int64)))).new

  # Reverse index for jobs by queue (e.g., vip, single-build, idle)
  property jobid_by_queue = Hash(String, Hash(String, Hash(Int8, Set(Int64)))).new

  # Cache for testbox information
  # keys "#{hostname}" are loaded from lab hosts/* yaml, then on-demand loaded from ES 'hosts' index
  property hosts_cache : Hosts
  property hosts_request = Hash(String, HostRequest).new

  # key: host_req.host_keys[]
  property user_sequence = Hash(String, Array(String)).new

  # key: host_machine
  property hostkey_sequence = Hash(String, Array(String)).new

  # queues enjoy "green channel", where jobs will be dispatched first when present
  GREEN_QUEUES = ["cluster", "vip", "single-build", "bisect"]

  property last_sync = Time.utc

  # TODO: populate real data
  property user_weights = Hash(String, UInt8).new

  def refresh_cache_from_es
    return if (Time.utc - @last_sync).seconds < 1

    # Update job counts by user. It could be more fine grained if necessary:
    # This is enough to avoid inter-user starvation, however not enough for
    # in-user starvation for jobs of different hw/vm/dc tbox and priority.
    # But one user should avoid 1000+ jobs in submit stage for long time in
    # the first place.
    nr_db_jobs_by_user : Hash(String, Int32) = @es.count_groups("jobs", "my_account", {"job_stage" => "submit"})

    total_jobs = nr_db_jobs_by_user.values.sum
    if (total_jobs < THRESH_JOBS_CACHE_IN_SUBMIT)
      # Refresh cache in one big batch
      pull_jobs_from_es({"job_stage" => "submit"}, THRESH_JOBS_CACHE_IN_SUBMIT + (THRESH_JOBS_CACHE_IN_SUBMIT >> 1))
    else
      # Selective refresh cache for users and hosts with empty queues
      nr_db_jobs_by_user.each do |user, count|
        if !user_has_job(user)
          pull_jobs_from_es({"my_account" => user, "job_stage" => "submit"})
        end
      end

    end

    @last_sync = Time.utc
  end

  # Iterate over @jobid_by_user[*][user][*] check if user has any job
  def user_has_job(user : String) : Bool
    # Iterate over all host keys
    @jobid_by_user.each_value do |user_jobs|
      # Check if the user exists in the middle hash
      if user_jobs.has_key?(user)
        # Iterate over all priorities for the user
        user_jobs[user].each_value do |job_set|
          # If any job set is not empty, the user has jobs
          return true unless job_set.empty?
        end
      end
    end
    false
  end

  def pull_jobs_from_es(matches, limit : Int32 = 1000)
    results = @es.select("jobs", matches, "LIMIT #{limit}")
    add_jobs_from_query(results)
  end

  def add_jobs_from_query(results)
    results.each do |hit|
      job = JobHash.new(hit["_source"].as_h)
      add_job(job)
    end
  end

  # providers/qemu.rb get_url "ws://#{DOMAIN_NAME}/ws/boot.ipxe?mac=#{mac}&hostname=#{hostname}&left_mem=#{left_mem}&tbox_type=vm&is_remote=true"
  def tbox_request_job(host_req : HostRequest)
    record_hostreq(host_req)
    job = try_dispatch_to(host_req)
    if job
      on_consumed_job(job)
    end
  end

  def record_hostreq(host_req : HostRequest)
    @hosts_request[host_req.full_hostname] = host_req
    @hosts_cache[host_req.host_machine].freemem = host_req.freemem
    host_req
  end

  def on_job_submit(job : JobHash)
    if add_job(job)
      # try_dispatch(job)
    end
  end

  # jobs are submit to either
  # - exact hw machine
  # - hw tbox_group
  # or
  # - some vm/dc offered by any hw machine
  # - some vm/dc, prefer some cache, may in some hw machines
  # - some vm/dc, must in some hw machines
  def try_dispatch_to(host_req : HostRequest) : JobHash?
    return nil if @jobs_cache_in_submit.empty?

    hostkeys = host_req.host_keys
    until hostkeys.empty?
      host_key = next_hostkey_to_try(host_req.host_machine, hostkeys)
      next unless host_key
      next unless hostkeys.delete host_key

      # Check priority queues first
      if job = consume_job_by_queues(GREEN_QUEUES, host_req, host_key)
        return job
      end

      if job = consume_job_by_users(host_req, host_key)
        return job
      end

      # Check idle queue last
      if job = consume_job_by_queues(["idle"], host_req, host_key)
        return job
      end
    end

    nil
  end

  private def consume_job_by_queues(queues : Array(String), host_req : HostRequest, host_key : String) : JobHash?
    return nil unless @jobid_by_queue.has_key? host_key

    jobid_by_queue = @jobid_by_queue[host_key]
    queues.each do |queue|
      next if jobid_by_queue[queue].empty?

      jobid_by_queue[queue].each do |job_id|
        job = @jobs_cache_in_submit[job_id]
        if match_job_to_host(job, host_req)
          return job
        end
      end
    end
    nil
  end

  private def consume_job_by_users(host_req : HostRequest, host_key : String) : JobHash?
    return nil unless @jobid_by_queue.has_key? host_key
    jobid_by_user = @jobid_by_user[host_key]

    users = jobid_by_user.keys
    until users.empty?
      user = next_user_to_try(host_key)
      next unless user
      next unless users.delete user
      next if jobid_by_user[user].empty?

      jobid_by_user[user].each do |job_id|
        job = @jobs_cache_in_submit[job_id]
        if match_job_to_host(job, host_req)
          return job
        end
      end
    end
  end

  private def match_job_to_host(job : JobHash, host_req : HostRequest) : Bool
    # job.schedule_tags.subset_of?(host_req.tags) &&
    job.schedule_memmb <= host_req.freemem
  end

  def next_user_to_try(host_key : String) : String?
    # If the sequence for this host_key already exists and has items, pop and return the next user
    if @user_sequence.has_key?(host_key) && !@user_sequence[host_key].empty?
      return @user_sequence[host_key].pop
    end

    # If no sequence exists, create one based on @jobid_by_user[host_key].keys and @user_weights
    users = @jobid_by_user[host_key].keys
    return nil if users.empty? # No users available for this host_key

    # Generate a weighted sequence
    sequence = [] of String
    users.each do |user|
      weight = @user_weights[user]? || 1 # Default weight is 1 if not specified
      weight.times { sequence << user }
    end

    # Shuffle the sequence to randomize the order while maintaining weight proportions
    sequence.shuffle!

    # Store the sequence for future use
    @user_sequence[host_key] = sequence

    # Pop and return the next user
    @user_sequence[host_key].pop
  end

  def next_hostkey_to_try(host_machine : String, host_keys : Array(String)) : String?
    # If the sequence for this host_machine already exists and has items, pop and return the next host_key
    if @hostkey_sequence.has_key?(host_machine) && !@hostkey_sequence[host_machine].empty?
      return @hostkey_sequence[host_machine].pop
    end

    # If no sequence exists, create one based on host_keys and their weights from @nr_jobs_by_hostkey
    return nil if host_keys.empty? # No host_keys available

    # Calculate weights for each host_key
    weights = host_keys.map do |host_key|
      # Get the number of jobs for this host_key (default to 0 if not found)
      nr_jobs = @nr_jobs_by_hostkey[host_key]? || 1
      [nr_jobs, 1].max
    end

    # Scale down the weights proportionally to ensure they fit within a reasonable range (e.g., 1-255)
    max_weight = weights.max
    if max_weight > (1 << 8) # control sequence size to around several times of 256
      weights = weights.map { |w| (w << 8) // max_weight }
    end

    # Generate a weighted sequence
    sequence = [] of String
    host_keys.each_with_index do |host_key, index|
      weight = weights[index]
      weight.times { sequence << host_key }
    end

    # Shuffle the sequence to randomize the order while maintaining weight proportions
    sequence.shuffle!

    # Store the sequence for future use
    @hostkey_sequence[host_machine] = sequence

    # Pop and return the next host_key
    @hostkey_sequence[host_machine].pop
  end

  def on_consumed_job(job : JobHash)
    job_id = job["id"].to_i64
    user = job["my_account"]
    queue = job["queue"]?

    if !@jobs_cache_in_submit.delete(job_id)
      @log.error "trying to delete non-existing job_id #{job_id}"
      return
    end

    job.host_keys.each do |hostkey|
      @nr_jobs_by_hostkey[hostkey] -= 1
      @jobid_by_user[hostkey][user][job.schedule_priority].delete(job_id)
      @jobid_by_queue[hostkey][queue][job.schedule_priority].delete(job_id) if queue
    end
  end

  def add_job(job : JobHash)
    job_id = job["id"].to_i64
    user = job["my_account"]
    queue = job["queue"]?

    to_consume = [] of String

    # Update indexes
    return if @jobs_cache_in_submit.has_key? job_id
    @jobs_cache_in_submit[job_id] = job

    job.set_tbox_type
    job.update_tbox_group_from_testbox
    job.set_memmb
    job.set_hostkeys
    job.set_priority

    host_keys = job.set_hostkeys
    host_keys.each do |hostkey|
      @nr_jobs_by_hostkey[hostkey] += 1
      to_consume << hostkey if @nr_jobs_by_hostkey[hostkey] == 1

      @jobid_by_user[hostkey] ||= Hash(String, Hash(Int8, Set(Int64))).new
      jobid_by_user = @jobid_by_user[hostkey]
      jobid_by_user[user][job.schedule_priority] ||= Set(Int64).new
      jobid_by_user[user][job.schedule_priority] << job_id

      if queue
        @jobid_by_queue[hostkey] ||= Hash(String, Hash(Int8, Set(Int64))).new
        jobid_by_queue = @jobid_by_queue[hostkey]
        jobid_by_queue[queue][job.schedule_priority] ||= Set(Int64).new
        jobid_by_queue[queue][job.schedule_priority] << job_id
      end

    end

    # Try immediate consumption
    to_consume
  end

end
