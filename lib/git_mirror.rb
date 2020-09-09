# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'bunny'
require 'json'
# gem install PriorityQueue
require 'priority_queue'
require 'English'

# worker threads
class GitMirror
  ERR_MESSAGE = <<~MESSAGE
    fatal: not a git repository (or any parent up to mount point /)
    Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
  MESSAGE
  ERR_CODE = 128

  def initialize(queue, feedback_queue)
    @queue = queue
    @feedback_queue = feedback_queue
    @feedback_info = {}
  end

  def feedback(git_repo, possible_new_refs)
    @feedback_info = { git_repo: git_repo, possible_new_refs: possible_new_refs }
    @feedback_queue.push(@feedback_info)
  end

  def git_clone(url, mirror_dir)
    ret = false
    10.times do
      ret = system("git clone --mirror #{url} #{mirror_dir}")
      break if ret
    end
    FileUtils.rm_r(mirror_dir) unless ret
    return ret
  end

  def git_fetch(mirror_dir)
    fetch_info = %x(git -C #{mirror_dir} fetch 2>&1)
    # Check whether mirror_dir is a good git repository by 3 conditions. If not, delete it.
    if ($CHILD_STATUS.exitstatus == ERR_CODE) && fetch_info.include?(ERR_MESSAGE) && Dir.empty?(mirror_dir)
      FileUtils.rmdir(mirror_dir)
    end
    return fetch_info.include? '->'
  end

  def mirror_sync
    fork_info = @queue.pop
    mirror_dir = "/srv/git/#{fork_info['forkdir']}.git"
    possible_new_refs = false
    if File.directory?(mirror_dir)
      possible_new_refs = git_fetch(mirror_dir)
    else
      FileUtils.mkdir_p(mirror_dir)
      possible_new_refs = git_clone(fork_info['url'], mirror_dir)
    end
    feedback(fork_info['forkdir'], possible_new_refs)
  end

  def git_mirror
    loop do
      mirror_sync
    end
  end
end

# main thread
class MirrorMain
  REPO_DIR = "#{ENV['LKP_SRC']}/repo"

  def initialize
    @feedback_queue = Queue.new
    @fork_stat = {}
    @priority = 0
    @priority_queue = PriorityQueue.new
    @git_info = {}
    @defaults = {}
    @git_queue = Queue.new
    load_fork_info
    connection = Bunny.new('amqp://172.17.0.1:5672')
    connection.start
    channel = connection.create_channel
    @message_queue = channel.queue('new_refs')
  end

  def fork_stat_init(stat_key)
    @fork_stat[stat_key] = {
      queued: false,
      priority: 0,
      fetch_time: nil,
      new_refs_time: nil
    }
  end

  def load_defaults(repodir)
    defaults_file = "#{repodir}/DEFAULTS"
    return unless File.exist?(defaults_file)

    project = repodir.delete_prefix("#{REPO_DIR}/")
    @defaults[project] = YAML.safe_load(File.open(defaults_file))
  end

  def load_repo_file(repodir, project, fork_name)
    @git_info["#{project}/#{fork_name}"] = YAML.safe_load(File.open(repodir))
    @git_info["#{project}/#{fork_name}"]['forkdir'] = "#{project}/#{fork_name}"
    @git_info["#{project}/#{fork_name}"].merge!(@defaults[project]) if @defaults[project]
    fork_stat_init("#{project}/#{fork_name}")
    @priority_queue.push "#{project}/#{fork_name}", @priority
    @priority += 1
  end

  def traverse_repodir(repodir)
    if File.directory? repodir
      load_defaults(repodir)
      entry_list = Dir.entries(repodir) - Array['.', '..', 'DEFAULTS', '.ignore']
      entry_list = Array['linus'] if File.basename(repodir) == 'linux'
      entry_list.each do |entry|
        traverse_repodir("#{repodir}/#{entry}")
      end
    else
      project = File.dirname(repodir).delete_prefix("#{REPO_DIR}/")
      fork_name = File.basename(repodir)
      load_repo_file(repodir, project, fork_name)
    end
  end

  def load_fork_info
    traverse_repodir(REPO_DIR)
  end

  def create_workers
    10.times do
      Thread.new do
        git_mirror = GitMirror.new(@git_queue, @feedback_queue)
        git_mirror.git_mirror
      end
      sleep(0.1)
    end
  end

  def send_message(feedback_info)
    message = feedback_info.to_json
    @message_queue.publish(message)
  end

  def handle_feedback
    return if @feedback_queue.empty?

    feedback_info = @feedback_queue.pop(true)
    @fork_stat[feedback_info[:git_repo]][:queued] = false
    return unless feedback_info[:possible_new_refs]

    new_refs = check_new_refs(feedback_info[:git_repo])
    return if new_refs[:heads].empty?

    feedback_info[:new_refs] = new_refs
    send_message(feedback_info)
  end

  def push_git_queue
    return if @git_queue.size >= 1

    fork_key = @priority_queue.delete_min_return_key
    unless @fork_stat[fork_key][:queued]
      @fork_stat[fork_key][:queued] = true
      @git_info[fork_key][:cur_refs] = get_cur_refs(fork_key) if @git_info[fork_key][:cur_refs].nil?
      @git_queue.push(@git_info[fork_key])
    end
    @priority_queue.push fork_key, @priority
    @priority += 1
  end

  def main_loop
    loop do
      push_git_queue
      handle_feedback
      sleep(0.1)
    end
  end
end

# main thread
class MirrorMain
  def compare_refs(cur_refs, old_refs)
    new_refs = { heads: {} }
    cur_refs[:heads].each do |ref, commit_id|
      if old_refs[:heads][ref] != commit_id
        new_refs[:heads][ref] = commit_id
      end
    end
    return new_refs
  end

  def get_cur_refs(git_repo)
    mirror_dir = "/srv/git/#{git_repo}.git"
    show_ref_out = %x(git -C #{mirror_dir} show-ref --heads)
    cur_refs = { heads: {} }
    show_ref_out.each_line do |line|
      next if line.start_with? '#'

      strings = line.split
      cur_refs[:heads][strings[1]] = strings.first
    end
    return cur_refs
  end

  def check_new_refs(git_repo)
    cur_refs = get_cur_refs(git_repo)
    new_refs = compare_refs(cur_refs, @git_info[git_repo][:cur_refs])
    @git_info[git_repo][:cur_refs] = cur_refs
    return new_refs
  end
end
