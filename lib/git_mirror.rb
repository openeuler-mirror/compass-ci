# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'bunny'
require 'json'
# gem install PriorityQueue
require 'priority_queue'

# worker threads
class GitMirror
  def initialize(queue, feedback_queue)
    @queue = queue
    @feedback_queue = feedback_queue
    @feedback_info = {}
    @new_refs = {}
  end

  # git show-ref --heads content example:
  # 9bedcbbf64d6d3270e645f7e04f13e61933f0c28 refs/heads/master
  def feedback(has_new_refs, git_repo)
    @feedback_info = { git_repo: git_repo }
    if has_new_refs
      @feedback_info[:new_refs] = @new_refs
    end
    @feedback_queue.push(@feedback_info)
  end

  def git_clone(url, mirror_dir)
    has_new_refs = false
    ret = false
    10.times do
      ret = system("git clone --mirror #{url} #{mirror_dir}")
      break if ret
    end
    if ret
      content = `git -C #{mirror_dir} show-ref --heads`
      has_new_refs = true
      get_all_refs(content)
    end
    return has_new_refs
  end

  def get_all_refs(content)
    @new_refs = { heads: {} }
    content.each_line do |line|
      next if line.start_with? '#'

      strings = line.split
      @new_refs[:heads][strings[1]] = strings.first
    end
  end

  def check_new_refs(fork_info, content)
    return false unless fork_info[:new_refs]

    @new_refs = { heads: {} }
    ret = false
    commits = fork_info[:new_refs][:heads]
    content.each_line do |line|
      next if line.start_with? '#'

      strings = line.split
      if commits[strings[1]] != strings.first
        @new_refs[:heads][strings[1]] = strings.first
        ret = true
      end
    end
    return ret
  end

  def git_fetch(mirror_dir, fork_info)
    has_new_refs = false
    ret = system("git -C #{mirror_dir} fetch")
    if ret
      content = `git -C #{mirror_dir} show-ref --heads`
      has_new_refs = check_new_refs(fork_info, content)
    end
    return has_new_refs
  end

  def mirror_sync
    fork_info = @queue.pop
    mirror_dir = "/srv/git/#{fork_info['forkdir']}.git"
    if File.directory?(mirror_dir)
      has_new_refs = git_fetch(mirror_dir, fork_info)
    else
      FileUtils.mkdir_p(mirror_dir)
      has_new_refs = git_clone(fork_info['url'], mirror_dir)
    end
    feedback(has_new_refs, fork_info['forkdir'])
  end

  def git_mirror
    loop do
      mirror_sync
    end
  end
end

# main thread
class MirrorMain
  def initialize
    @feedback_queue = Queue.new
    @fork_stat = {}
    @priority = 0
    @priority_queue = PriorityQueue.new
    @git_info = {}
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

  def load_project_dir(repodir, project)
    project_dir = "#{repodir}/#{project}"
    fork_list = Dir.entries(project_dir) - Array['.', '..', 'DEFAULTS', '.ignore']
    fork_list = Array['linus'] if project == 'linux'
    fork_list.each do |fork_name|
      @git_info["#{project}/#{fork_name}"] = YAML.safe_load(File.open("#{project_dir}/#{fork_name}"))
      @git_info["#{project}/#{fork_name}"]['forkdir'] = "#{project}/#{fork_name}"
      fork_stat_init("#{project}/#{fork_name}")
      @priority_queue.push "#{project}/#{fork_name}", @priority
      @priority += 1
    end
  end

  def load_fork_info
    repodir = "#{ENV['LKP_SRC']}/repo"
    project_list = Dir.entries(repodir) - Array['.', '..']
    project_list.each do |project|
      load_project_dir(repodir, project)
    end
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

  def memmory_all_refs(git_repo)
    mirror_dir = "/srv/git/#{git_repo}.git"
    content = `git -C #{mirror_dir} show-ref --heads`
    new_refs = { heads: {} }
    content.each_line do |line|
      next if line.start_with? '#'

      strings = line.split
      new_refs[:heads][strings[1]] = strings.first
    end
    return new_refs
  end

  def handle_feedback
    return if @feedback_queue.empty?

    feedback_info = @feedback_queue.pop(true)
    @fork_stat[feedback_info[:git_repo]][:queued] = false
    @git_info[feedback_info[:git_repo]][:new_refs] = memmory_all_refs(feedback_info[:git_repo])
    return unless feedback_info[:new_refs]

    send_message(feedback_info)
  end

  def push_git_queue
    return if @git_queue.size >= 1

    fork_key = @priority_queue.delete_min_return_key
    unless @fork_stat[fork_key][:queued]
      @fork_stat[fork_key][:queued] = true
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
