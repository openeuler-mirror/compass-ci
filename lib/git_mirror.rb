# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'bunny'
require 'json'
# gem install PriorityQueue
require 'priority_queue'
require 'English'
require 'elasticsearch'
require_relative 'constants.rb'

# worker threads
class GitMirror
  ERR_MESSAGE = <<~MESSAGE
    fatal: not a git repository (or any parent up to mount point /srv)
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
    url = Array(url)[0]
    if url.include?('gitee.com/') && File.exist?("/srv/git/#{url.delete_prefix('https://')}")
      url = "/srv/git/#{url.delete_prefix('https://')}"
    end
    10.times do
      ret = system("git clone --mirror #{url} #{mirror_dir}")
      break if ret
    end
    FileUtils.rm_r(mirror_dir) unless ret
    return ret
  end

  def git_fetch(mirror_dir)
    fetch_info = %x(git -C #{mirror_dir} fetch 2>&1)
    # Check whether mirror_dir is a good git repository by 2 conditions. If not, delete it.
    if fetch_info.include?(ERR_MESSAGE) && Dir.empty?(mirror_dir)
      FileUtils.rmdir(mirror_dir)
    end
    return fetch_info.include? '->'
  end

  def mirror_sync
    fork_info = @queue.pop
    mirror_dir = "/srv/git/#{fork_info['git_repo']}.git"
    possible_new_refs = false
    if File.directory?(mirror_dir)
      possible_new_refs = git_fetch(mirror_dir)
    else
      FileUtils.mkdir_p(mirror_dir)
      possible_new_refs = git_clone(fork_info['url'], mirror_dir)
    end
    feedback(fork_info['git_repo'], possible_new_refs)
  end

  def git_mirror
    loop do
      mirror_sync
    end
  end
end

# main thread
class MirrorMain
  REPO_DIR = ENV['REPO_SRC']

  def initialize
    @feedback_queue = Queue.new
    @fork_stat = {}
    @priority = 0
    @priority_queue = PriorityQueue.new
    @git_info = {}
    @defaults = {}
    @git_queue = Queue.new
    @es_client = Elasticsearch::Client.new(url: "http://#{ES_HOST}:#{ES_PORT}")
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

  def traverse_repodir(repodir)
    if File.directory? repodir
      load_defaults(repodir)
      entry_list = Dir.entries(repodir) - Array['.', '..', 'DEFAULTS', '.ignore', '.git']
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
    feedback_info.merge!(@git_info[feedback_info[:git_repo]])
    feedback_info.delete(:cur_refs)
    message = feedback_info.to_json
    @message_queue.publish(message)
  end

  def handle_feedback
    return if @feedback_queue.empty?

    feedback_info = @feedback_queue.pop(true)
    git_repo = feedback_info[:git_repo]
    @fork_stat[git_repo][:queued] = false
    return unless feedback_info[:possible_new_refs]

    @fork_stat[git_repo][:priority] += 1
    return reload_fork_info if git_repo == 'upstream-repos/upstream-repos'

    new_refs = check_new_refs(git_repo)
    return if new_refs[:heads].empty?

    feedback_info[:new_refs] = new_refs
    send_message(feedback_info)
  end

  def do_push(fork_key)
    @fork_stat[fork_key][:queued] = true
    @git_info[fork_key][:cur_refs] = get_cur_refs(fork_key) if @git_info[fork_key][:cur_refs].nil?
    @git_queue.push(@git_info[fork_key])
  end

  def push_git_queue
    return if @git_queue.size >= 1

    fork_key = @priority_queue.delete_min_return_key
    do_push(fork_key) unless @fork_stat[fork_key][:queued]
    @priority_queue.push fork_key, (@priority - @fork_stat[fork_key][:priority])
    @priority += 1
  end

  def main_loop
    loop do
      push_git_queue
      handle_feedback
      Signal.trap(:SIGCHLD, 'SIG_IGN')
    end
  end
end

# main thread
class MirrorMain
  def load_repo_file(repodir, project, fork_name)
    git_repo = "#{project}/#{fork_name}"
    @git_info[git_repo] = YAML.safe_load(File.open(repodir))
    @git_info[git_repo]['git_repo'] = git_repo
    @git_info[git_repo].merge!(@defaults[project]) if @defaults[project]
    es_repo_update(git_repo, @git_info[git_repo])
    fork_stat_init(git_repo)
    @priority_queue.push git_repo, @priority
    @priority += 1
  end

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

  def reload_fork_info
    upstream_repos = 'upstream-repos/upstream-repos'
    if @git_info[upstream_repos][:cur_refs].empty?
      @git_info[upstream_repos][:cur_refs] = get_cur_refs(upstream_repos)
    else
      old_commit = @git_info[upstream_repos][:cur_refs][:heads]['refs/heads/master']
      new_refs = check_new_refs(upstream_repos)
      new_commit = new_refs[:heads]['refs/heads/master']
      changed_files = %x(git -C /srv/git/#{upstream_repos}.git diff --name-only #{old_commit}...#{new_commit})
      reload(changed_files)
    end
  end

  def reload(file_list)
    system("git -C #{REPO_DIR} pull")
    file_list.each_line do |file|
      next if File.basename(file) == '.ignore'

      repo_dir = "#{REPO_DIR}/#{file}"
      load_repo_file(repo_dir, File.dirname(file), File.basename(file)) if File.file?(repo_dir)
    end
  end

  def es_repo_update(git_repo, repo_info)
    body = {
      "doc": repo_info,
      "doc_as_upsert": true
    }
    @es_client.update(index: 'repo', type: '_doc', id: git_repo, body: body)
  end
end
