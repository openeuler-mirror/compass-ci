# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.

require "set"
require "json"
require "./host"
require "./sched"

# a host's job request parameters
struct HostRequest
  include JSON::Serializable

  property arch : String

  # e.g. taishan200-2280-2s64p-256g--a61
  property hostname : String

  # e.g. hw | vm | dc | vm,dc
  property tbox_type : String

  # [hostname, tbox_group, hw.$arch] for hw
  # vm.$arch | dc.$arch for vm | dc
  @[JSON::Field(ignore_deserialize: true)]
  property host_keys = Array(String).new
  @[JSON::Field(ignore_deserialize: true)]
  property time : Int64 = 0

  property is_remote : Bool
  property tags : Set(String)
  property freemem : UInt32 # unit: MB, duplicates metrics.freemem for fast access

  property metrics : Hash(String, UInt32)
  property services : Hash(String, String)
  property disk_max_used_string : String

  def initialize(@arch, @hostname, @tbox_type, tags, @freemem, @is_remote, sched_host, sched_port)
    set_host_keys
    @tags = Set(String).new tags.split(",")

    @disk_max_used_string = ""
    @metrics = Hash(String, UInt32).new

    @services = Hash(String, String).new
    @services["sched_host"] = sched_host
    @services["sched_port"] = sched_port
    @services["result_host"] = sched_host
    @services["result_port"] = sched_port
  end

  def set_host_keys
    if @tbox_type == "hw"
      tbox_group = JobHelper.match_tbox_group(@hostname.sub(/-\d+$/, ""))
      @host_keys = [ @hostname, tbox_group, "hw.#{@arch}" ]
    else
      # refer to doc/job/fields/testbox.md
      @host_keys = [ @hostname ]
      @tbox_type.split(",") { |t| @host_keys << "#{t}.#{@arch}" }
    end
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
  @host_requests = [] of HostRequest  # Using sorted array instead of PriorityQueue

  # key: host_req.host_keys[]
  property user_sequence = Hash(String, Array(String)).new

  # key: hostname
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
      add_job_to_cache(job)
    end
  end

  def tbox_request_job(host_req : HostRequest)
    # the assignment is necessary to get back the changed host_req
    host_req = record_hostreq(host_req)
    job = choose_job_for(host_req)
    if job
      dispatch_job(host_req, job)
    end
    job
  end

  def record_hostreq(host_req : HostRequest)
    hostname = host_req.hostname
    host_req.time = Time.local.to_unix
    host_req.set_host_keys
    @hosts_request[hostname] = host_req
    host_req
  end

  # jobs are submit to either
  # - exact hw machine
  # - hw tbox_group
  # or
  # - some vm/dc offered by any hw machine
  # - some vm/dc, prefer some cache, may in some hw machines
  # - some vm/dc, must in some hw machines
  def choose_job_for(host_req : HostRequest) : JobHash?
    return nil if @jobs_cache_in_submit.empty?

    hostkeys = host_req.host_keys
    until hostkeys.empty?
      host_key = next_hostkey_to_try(host_req.hostname, hostkeys)
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

      jobid_by_queue[queue].each do |priority, job_set|
        job_set.each do |job_id|
          job = @jobs_cache_in_submit[job_id]
          if match_job_to_host(job, host_req)
            return job
          end
        end
      end
    end
    nil
  end

  private def consume_job_by_users(host_req : HostRequest, host_key : String) : JobHash?
    return nil unless @jobid_by_user.has_key? host_key
    jobid_by_user = @jobid_by_user[host_key]

    users = jobid_by_user.keys
    until users.empty?
      user = next_user_to_try(host_key)
      next unless user
      next unless users.delete user
      next if jobid_by_user[user].empty?

      # Iterate over each priority and job set
      jobid_by_user[user].each do |priority, job_set|
        # @log.debug { "Checking user=#{user}, priority=#{priority}, jobs=#{job_set.size}" }
        job_set.each do |job_id|
          job = @jobs_cache_in_submit[job_id]
          if match_job_to_host(job, host_req)
            return job
          end
        end
      end
    end
  end

  private def match_job_to_host(job : JobHash, host_req : HostRequest) : Bool
    # job.schedule_tags.subset_of?(host_req.tags) &&
    job.schedule_memmb <= host_req.freemem
  end

  # Deterministically interleaves users based on their weights to create an
  # evenly distributed sequence while maintaining weight proportions.
  #
  # Targets:
  # - Eliminate randomness while preserving weight-based distribution
  # - Ensure users are spaced as evenly as possible in the resulting sequence
  # - Maintain strict determinism for same input weights and user order
  #
  # Key Considerations:
  # - Weight proportionality: Higher weighted users appear more frequently
  # - Even distribution: Avoid clustering of user entries
  # - Deterministic ties: Use lexicographical user order for position conflicts
  # - Efficiency: O(n log n) complexity for typical use cases
  #
  # Algorithm Overview:
  # 1. Position Calculation:
  #    - For each user entry, calculate a virtual position using:
  #      `(entry_index + 0.5) * (total_weight / user_weight)`
  #    - This spreads entries proportionally based on their relative weights
  # 2. Sorting:
  #    - Sort all entries by calculated positions
  #    - Break position ties using user identifier comparison
  # 3. Sequence Generation:
  #    - Extract sorted user identifiers to create final sequence
  #
  # Design Notes:
  # - Inspired by content-aware image resampling and stride scheduling
  # - Maintains weight ratios through mathematical distribution rather than chance
  # - 0.5 offset in position calculation prevents edge-clustering
  # - User order comparison ensures determinism for equal-position entries
  #
  # Example:
  # - Weights: UserA(3), UserB(2) → Sequence: A, B, A, B, A
  # - Weights: UserX(4), UserY(1) → Sequence: X, X, Y, X, X
  #
  # See: "Deterministic Weighted Distribution Algorithms" (CS theory)
  # and "Fair Sequence Scheduling" patterns for conceptual background
  def self.create_users_sequence(users, weights)
    # Calculate the total weight from all users
    total_weight = users.sum { |user| weights[user]? || 1 }

    # Generate tuples of calculated positions and users
    positioned_users = [] of Tuple(Float64, String)
    users.each do |user|
      weight = weights[user]? || 1
      weight.times do |i|
        # Calculate position using weighted distribution formula
        position = (i.to_f + 0.5) * (total_weight.to_f / weight.to_f)
        positioned_users << {position, user}
      end
    end

    # Sort by position and user to ensure deterministic order
    positioned_users.sort_by! { |entry| {entry[0], entry[1]} }

    # Extract the sorted user sequence
    positioned_users.map { |entry| entry[1] }
  end

  def next_user_to_try(host_key : String) : String?
    # If the sequence for this host_key already exists and has items, pop and return the next user
    if @user_sequence.has_key?(host_key) && !@user_sequence[host_key].empty?
      return @user_sequence[host_key].pop
    end

    # If no sequence exists, create one based on @jobid_by_user[host_key].keys and @user_weights
    users = @jobid_by_user[host_key].keys
    return nil if users.empty? # No users available for this host_key

    # Store the sequence for future use
    @user_sequence[host_key] = Sched.create_users_sequence(users, @user_weights)
    # @log.debug { "create_users_sequence #{@user_sequence[host_key]}" }

    # Pop and return the next user
    @user_sequence[host_key].pop
  end

  # Generates a deterministic sequence of host keys with even interleaving based on their job counts.
  #
  # Target:
  # - Ensure higher job count hosts are evenly distributed in the sequence to avoid clustering.
  # - Replace randomness with deterministic even interleaving to maintain predictable order.
  #
  # Considerations:
  # - Uses square root of job counts to compute weights, favoring smooth distribution over abrupt changes.
  # - Scales weights to a manageable range (1-255) to prevent sequences from becoming excessively long.
  # - Maintains weight proportionality after scaling to preserve the relative job distribution.
  # - Sorts events by calculated positions and host index to break ties and ensure determinism.
  #
  # Algorithm/Design:
  # 1. Calculate host key weights using the square root of their job counts, ensuring a minimum weight of 1.
  # 2. Scale weights proportionally if the maximum weight exceeds 255 to keep the sequence size reasonable.
  # 3. Generate events for each host key with positions spaced according to their scaled weights.
  # 4. Sort events by calculated position, then by host index to achieve even interleaving and order.
  #
  # Example:
  # For host keys `A` and `B` with job counts 9 and 1:
  # - Weights: sqrt(9)=3, sqrt(1)=1 (scaled weights 3 and 1).
  # - Events: `A` at positions 0, 1.333, 2.666; `B` at position 0.
  # - Sorted sequence: `[A, B, A, A]`, showcasing deterministic interleaving.
  def self.generate_interleaved_sequence(host_keys : Array(String),
                                         nr_jobs_by_hostkey : Hash(String, Int32)) : Array(String)
    # Calculate weights for each host_key
    weights = host_keys.map do |host_key|
      Math.sqrt(nr_jobs_by_hostkey.has_key?(host_key) ?
                nr_jobs_by_hostkey[host_key] : 1).to_i32
    end

    # Scale down the weights proportionally to ensure they fit within a reasonable range (1-255)
    max_weight = weights.max
    if max_weight > (1 << 8) # Control sequence size to around several times of 256
      weights = weights.map { |w| (w << 8) // max_weight }
    end

    # Compute total_events as sum of scaled weights
    total_events = weights.sum

    # Generate events with positions
    events = [] of Tuple(Float64, String, Int32)
    host_keys.each_with_index do |host_key, host_index|
      weight = weights[host_index]
      step = total_events.to_f / weight
      weight.times do |i|
        pos = i * step
        events << {pos, host_key, host_index}
      end
    end

    # Sort events by position, then by host index to break ties
    sorted_events = events.sort do |a, b|
      pos_a, _, idx_a = a
      pos_b, _, idx_b = b
      if pos_a != pos_b
        pos_a <=> pos_b
      else
        idx_a <=> idx_b
      end
    end

    # Extract the host_keys from the sorted events
    sorted_events.map { |e| e[1] }
  end

  def next_hostkey_to_try(host_machine : String, host_keys : Array(String)) : String?
    # If the sequence for this host_machine already exists and has items, pop and return the next host_key
    if @hostkey_sequence.has_key?(host_machine) && !@hostkey_sequence[host_machine].empty?
      return @hostkey_sequence[host_machine].pop
    end

    # If no sequence exists, create one based on host_keys and their weights from @nr_jobs_by_hostkey
    return nil if host_keys.empty? # No host_keys available

    # Store the sequence for future use
    @hostkey_sequence[host_machine] = Sched.generate_interleaved_sequence(host_keys, @nr_jobs_by_hostkey)
    # @log.debug { "generate_interleaved_sequence #{@hostkey_sequence[host_machine]}" }

    # Pop and return the next host_key
    @hostkey_sequence[host_machine].pop
  end

  def on_job_submit(job : JobHash)
    job.delete_account_info
    save_secrets(job)
    @es.insert_doc("jobs", job)
    add_job_to_cache(job)
  end

  # Called for es fetched jobs, new or updated jobs.
  # Both may may already been cached.
  def add_job_to_cache(job : JobHash)
    job_id = job.id64

    # Waiting on other jobs?
    if job.hash_hhh.has_key?("wait_on")
      return if @jobs_cache.has_key?(job_id)
      @jobs_cache[job_id] = job
      register_wait_on_job(job, job_id)
      return # Not ready for scheduling
    end

    # Cache running jobs
    if job.job_stage != "submit"
      return if @jobs_cache.has_key?(job_id)
      @jobs_cache[job_id] = job
      return
    end

    # Create data structures for job scheduling
    return if @jobs_cache_in_submit.has_key?(job_id)
    @jobs_cache_in_submit[job_id] = job

    set_job_schedule_properties(job)
    create_job_schedule_indices(job, job_id)
  end

  # on job consume, move job from dispatch data structures
  # to the next stage @jobs_cache[]
  def move_job_cache(job : JobHash)
    job_id = job.id64

    remove_job_schedule_indices(job, job_id)
    @jobs_cache[job_id] = job
  end

  private def set_job_schedule_properties(job : JobHash)
    job.set_tbox_type
    job.set_memmb
    job.set_hostkeys
    job.set_priority
  end

  private def register_wait_on_job(job : JobHash, job_id : Int64)
    job.wait_on.each do |id, _|
      id = id.to_i64
      @jobs_wait_on[id] = Set(Int64).new
      @jobs_wait_on[id] << job_id
    end
  end

  private def remove_job_schedule_indices(job, job_id)
    return if !@jobs_cache_in_submit.delete(job_id)

    user = job["my_account"]
    queue = job["queue"]?
    job.host_keys.each do |hostkey|
      @nr_jobs_by_hostkey[hostkey] -= 1
      @jobid_by_user[hostkey][user][job.schedule_priority].delete(job_id)
      @jobid_by_queue[hostkey][queue][job.schedule_priority].delete(job_id) if queue
    end
  end

  private def create_job_schedule_indices(job : JobHash, job_id : Int64)
    user = job["my_account"]
    queue = job["queue"]?
    job.set_hostkeys.each do |hostkey|
      update_hostkey_indices(hostkey)
      update_user_indices(job, job_id, user, hostkey)
      update_queue_indices(job, job_id, queue, hostkey) if queue
    end
  end

  private def update_hostkey_indices(hostkey : String)
    @nr_jobs_by_hostkey[hostkey] += 1

    # if some hw host is waiting job, wakeup dispatch_worker for it
    if @hw_machine_channels.has_key?(hostkey)
      @host_request_job_channel.send(@hosts_request[hostkey])
    end
  end

  private def update_user_indices(job : JobHash, job_id : Int64, user : String, hostkey : String)
    # Update user-specific indices
    @jobid_by_user[hostkey] ||= Hash(String, Hash(Int8, Set(Int64))).new
    user_jobs = @jobid_by_user[hostkey]
    user_jobs[user] ||= Hash(Int8, Set(Int64)).new
    user_jobs[user][job.schedule_priority] ||= Set(Int64).new
    user_jobs[user][job.schedule_priority] << job_id
  end

  private def update_queue_indices(job : JobHash, job_id : Int64, queue : String, hostkey : String)
    # Update queue-specific indices if queue is present
    @jobid_by_queue[hostkey] ||= Hash(String, Hash(Int8, Set(Int64))).new
    queue_jobs = @jobid_by_queue[hostkey]
    queue_jobs[queue] ||= Hash(Int8, Set(Int64)).new
    queue_jobs[queue][job.schedule_priority] ||= Set(Int64).new
    queue_jobs[queue][job.schedule_priority] << job_id
  end

  def dispatch_worker
    loop do
      # Step 1: Collect all pending host requests
      collect_host_requests

      # Step 2: Process jobs only if we have both jobs and hosts
      if !@jobs_cache_in_submit.empty?
        find_dispatch_jobs
      else
        # Sleep to prevent busy looping when no work
        sleep 0.1.seconds
      end
    end
  end

  private def collect_host_requests
    # Non-blocking read all pending host requests
    while hostreq = @host_request_job_channel.receive?
      add_hostreq(hostreq)
    end

    # Block read to prevent busy looping when no work
    while @host_requests.empty?
      hostreq = @host_request_job_channel.receive
      add_hostreq(hostreq)
    end

  rescue Channel::ClosedError
    @log.info { "Host request channel closed" }
  end

  private def add_hostreq(hostreq)
      # Only consider hosts with sufficient resources
      if hostreq.freemem >= 3000
        # Maintain sorted order by freemem (descending)
        index = @host_requests.bsearch_index { |x| x.freemem > hostreq.freemem } || @host_requests.size
        @host_requests.insert(index, hostreq)
      end
  end

  private def find_dispatch_jobs
    # Process hosts in freemem order
    while hostreq = @host_requests.pop?
      job = choose_job_for(hostreq)
      next unless job

      # Dispatch the job
      if dispatch_job(hostreq, job)
        # Update host resources
        hostreq.freemem -= job.schedule_memmb

        # Re-add to queue if still has capacity
        add_hostreq(hostreq)
      end

      break if @jobs_cache_in_submit.empty?
    end
  end

  private def dispatch_job(hostreq : HostRequest, job : JobHash) : Bool
    case job.tbox_type
    when "hw"
      if channel = @hw_machine_channels[hostreq.hostname]?
        channel.send(job)
        true
      else
        @log.error { "HW channel not found for #{hostreq.hostname}" }
        false
      end
    when "vm", "dc"
      if provider = @provider_sessions[hostreq.hostname]?
        on_job_dispatch(job, hostreq)
        msg = boot_content(job, job.tbox_type)
        if job.tbox_type == "vm"
          msg = { "type" => "boot-job",
                  "ipxe_script" => msg,
                  "job_id" => job.id,
                  "job_token" => job.job_token,
                  "result_root" => job.result_root,
                  "tbox_type" => "vm",
                  "tbox_group" => job.tbox_group,
          }.to_json
        end
        provider.socket.send(msg)
        true
      else
        @log.error { "Provider not found for #{hostreq.hostname}" }
        false
      end
    else
      @log.error { "Unknown tbox_type: #{job.tbox_type}" }
      false
    end
  rescue ex
    @log.error(exception: ex) { "Failed to dispatch job #{job.id}" }
    false
  end

	# debug dump dispatch data structures
	def api_debug_dispatch(env)
		str = "
@jobs_cache_in_submit.keys: #{@jobs_cache_in_submit.keys.to_pretty_json}\n
@nr_jobs_by_hostkey: #{@nr_jobs_by_hostkey.to_pretty_json}\n
@jobid_by_user: #{@jobid_by_user.to_pretty_json}\n
@jobid_by_queue: #{@jobid_by_queue.to_pretty_json}\n
@hosts_request: #{@hosts_request.to_pretty_json}\n
@host_requests: #{@host_requests.to_pretty_json}\n
@user_sequence: #{@user_sequence.to_pretty_json}\n
@hostkey_sequence: #{@hostkey_sequence.to_pretty_json}\n
@user_weights: #{@user_weights.to_pretty_json}\n

@jobs_cache.keys: #{@jobs_cache.keys.to_pretty_json}\n
@jobs_wait_on: #{@jobs_wait_on.to_pretty_json}\n
@client_sessions.keys: #{@client_sessions.keys.to_pretty_json}\n
@provider_sessions.keys: #{@provider_sessions.keys.to_pretty_json}\n
@console_jobid2client_sid: #{@console_jobid2client_sid.to_pretty_json}\n
@watchlog_jobid2client_sids: #{@watchlog_jobid2client_sids.to_pretty_json}\n
@watchjob_jobid2client_sids: #{@watchjob_jobid2client_sids.to_pretty_json}\n
@hw_machine_channels.keys: #{@hw_machine_channels.keys.to_pretty_json}\n
@wait_client_channel.keys: #{@wait_client_channel.keys.to_pretty_json}\n
@wait_client_spec: #{@wait_client_spec.to_pretty_json}\n
"
  end

end
