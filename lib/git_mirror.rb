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

  def get_url(url)
    if url.include?('gitee.com/') && File.exist?("/srv/git/#{url.delete_prefix('https://')}")
      url = "/srv/git/#{url.delete_prefix('https://')}"
    end
    return url
  end

  def git_clone(url, mirror_dir)
    url = get_url(Array(url)[0])
    10.times do
      %x(git clone --mirror --depth 1 #{url} #{mirror_dir} 2>&1)
      return true if File.directory?(mirror_dir) && File.exist?("#{mirror_dir}/config")
    end
    return false
  end

  def git_fetch(mirror_dir)
    if File.exist?("#{mirror_dir}/shallow")
      %x(git -C #{mirror_dir} fetch --unshallow 2>&1)
      return false
    end

    fetch_info = %x(git -C #{mirror_dir} fetch 2>&1)
    # Check whether mirror_dir is a good git repository by 2 conditions. If not, delete it.
    if fetch_info.include?(ERR_MESSAGE) && Dir.empty?(mirror_dir)
      FileUtils.rmdir(mirror_dir)
    end
    return fetch_info.include? '->'
  end

  def url_changed?(url, mirror_dir)
    url = get_url(Array(url)[0])
    git_url = %x(git -C #{mirror_dir} ls-remote --get-url origin).chomp

    return true if url == git_url

    return false
  end

  def git_repo_download(url, mirror_dir)
    return git_clone(url, mirror_dir) unless File.directory?(mirror_dir)

    return git_fetch(mirror_dir) if url_changed?(url, mirror_dir)

    FileUtils.rm_r(mirror_dir)
    return git_clone(url, mirror_dir)
  end

  def mirror_sync
    fork_info = @queue.pop
    mirror_dir = "/srv/git/#{fork_info['git_repo']}"
    mirror_dir = "#{mirror_dir}.git" unless fork_info['is_submodule']
    possible_new_refs = git_repo_download(fork_info['url'], mirror_dir)
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
    connection_init
    handle_webhook
  end

  def connection_init
    connection = Bunny.new('amqp://172.17.0.1:5672')
    connection.start
    channel = connection.create_channel
    @message_queue = channel.queue('new_refs')
    @webhook_queue = channel.queue('web_hook')
  end

  def fork_stat_init(git_repo)
    @fork_stat[git_repo] = get_fork_stat(git_repo)
  end

  def load_defaults(repodir)
    defaults_file = "#{repodir}/DEFAULTS"
    return unless File.exist?(defaults_file)

    defaults_key = repodir == REPO_DIR ? 'default' : repodir.delete_prefix("#{REPO_DIR}/")
    @defaults[defaults_key] = YAML.safe_load(File.open(defaults_file))
    @defaults[defaults_key] = merge_defaults(defaults_key, @defaults[defaults_key])
  end

  def traverse_repodir(repodir)
    if File.directory? repodir
      load_defaults(repodir)
      entry_list = Dir.children(repodir) - ['DEFAULTS']
      entry_list.each do |entry|
        next if entry.start_with? '.'

        traverse_repodir("#{repodir}/#{entry}")
      end
    else
      return if File.dirname(repodir) == REPO_DIR

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
    return if check_submodule(git_repo)

    update_fork_stat(git_repo, feedback_info[:possible_new_refs])
    return unless feedback_info[:possible_new_refs]

    return reload_fork_info if git_repo == 'u/upstream-repos/upstream-repos'

    new_refs = check_new_refs(git_repo)
    return if new_refs[:heads].empty?

    feedback_info[:new_refs] = new_refs
    send_message(feedback_info)
  end

  def do_push(fork_key)
    return if @fork_stat[fork_key][:queued]

    @fork_stat[fork_key][:queued] = true
    @git_info[fork_key][:cur_refs] = get_cur_refs(fork_key) if @git_info[fork_key][:cur_refs].nil?
    @git_queue.push(@git_info[fork_key])
  end

  def push_git_queue
    return if @git_queue.size >= 1

    fork_key = @priority_queue.delete_min_return_key
    do_push(fork_key)
    priority_set = @priority > @fork_stat[fork_key][:priority] ? (@priority - @fork_stat[fork_key][:priority]) : 1
    @priority_queue.push fork_key, priority_set
    @priority += 1
  end

  def main_loop
    loop do
      push_git_queue
      handle_feedback
      Signal.trap(:SIGCHLD, 'SIG_IGN')
      sleep(0.1)
    end
  end
end

# main thread
class MirrorMain
  def load_repo_file(repodir, project, fork_name)
    git_repo = "#{project}/#{fork_name}"
    git_info = YAML.safe_load(File.open(repodir))
    return if git_info.nil? || git_info['url'].nil?

    @git_info[git_repo] = git_info
    @git_info[git_repo]['git_repo'] = git_repo
    @git_info[git_repo] = merge_defaults(git_repo, @git_info[git_repo])
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
    return if @git_info[git_repo]['is_submodule']

    mirror_dir = "/srv/git/#{git_repo}.git"
    show_ref_out = %x(git -C #{mirror_dir} show-ref --heads 2>/dev/null)
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
    upstream_repos = 'u/upstream-repos/upstream-repos'
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

      file = file.chomp
      repo_dir = "#{REPO_DIR}/#{file}"
      load_repo_file(repo_dir, File.dirname(file), File.basename(file)) if File.file?(repo_dir)
    end
  end

  def es_repo_update(git_repo)
    repo_info = { 'git_repo' => git_repo, 'url' => @git_info[git_repo]['url'] }
    repo_info = repo_info.merge(@fork_stat[git_repo])
    body = {
      "doc": repo_info,
      "doc_as_upsert": true
    }
    @es_client.update(index: 'repo', type: '_doc', id: git_repo, body: body)
  end

  def update_stat_fetch(git_repo)
    @fork_stat[git_repo][:queued] = false
    offset_fetch = @fork_stat[git_repo][:offset_fetch]
    offset_fetch = 0 if offset_fetch >= 10
    @fork_stat[git_repo][:fetch_time][offset_fetch] = Time.now.to_s
    @fork_stat[git_repo][:offset_fetch] = offset_fetch + 1
  end

  def update_stat_new_refs(git_repo)
    @fork_stat[git_repo][:priority] += 1
    offset_new_refs = @fork_stat[git_repo][:offset_new_refs]
    offset_new_refs = 0 if offset_new_refs >= 10
    @fork_stat[git_repo][:new_refs_time][offset_new_refs] = Time.now.to_s
    @fork_stat[git_repo][:offset_new_refs] = offset_new_refs + 1
    @fork_stat[git_repo][:new_refs_count] = update_new_refs_count(@fork_stat[git_repo][:new_refs_count])
  end

  def update_fork_stat(git_repo, possible_new_refs)
    update_stat_fetch(git_repo)
    update_stat_new_refs(git_repo) if possible_new_refs
    es_repo_update(git_repo)
  end
end

# main thread
class MirrorMain
  def check_git_repo(git_repo, webhook_url)
    return @git_info.key?(git_repo) && Array(@git_info[git_repo]['url'])[0] == webhook_url
  end

  # example
  # url: https://github.com/berkeley-abc/abc         git_repo: a/abc/abc
  # url: https://github.com/Siguyi/AvxToNeon         git_repo: a/AvxToNeon/Siguyi
  def get_git_repo(webhook_url)
    return webhook_url.split(':')[1].gsub(' ', '') if webhook_url =~ /^(git_repo:)/

    fork_name, project = webhook_url.split('/')[-2, 2]

    git_repo = "#{project[0].downcase}/#{project}/#{fork_name}"
    return git_repo if check_git_repo(git_repo, webhook_url)

    git_repo = "#{project[0].downcase}/#{project}/#{project}"
    return git_repo if check_git_repo(git_repo, webhook_url)

    puts "webhook: #{webhook_url} is not found!"
  end

  def handle_webhook
    Thread.new do
      @webhook_queue.subscribe(block: true) do |_delivery, _properties, webhook_url|
        git_repo = get_git_repo(webhook_url)
        do_push(git_repo) if git_repo
        sleep(0.1)
      end
    end
  end

  def handle_submodule(submodule)
    submodule.each_line do |line|
      next unless line.include?('url = ')

      url = line.split(' = ')[1].chomp
      git_repo = url.split('://')[1] if url.include?('://')
      break unless git_repo

      @git_info[git_repo] = { 'url' => url, 'git_repo' => git_repo, 'is_submodule' => true }
      fork_stat_init(git_repo)
      @priority_queue.push git_repo, @priority
      @priority += 1
    end
  end

  def check_submodule(git_repo)
    if @git_info[git_repo]['is_submodule']
      @fork_stat[git_repo][:queued] = false
      return true
    end

    mirror_dir = "/srv/git/#{git_repo}.git"
    submodule = %x(git -C #{mirror_dir} show HEAD:.gitmodules 2>/dev/null)
    return if submodule.empty?

    handle_submodule(submodule)
  end

  def get_fork_stat(git_repo)
    fork_stat = {
      queued: false,
      priority: 0,
      fetch_time: [],
      offset_fetch: 0,
      new_refs_time: [],
      offset_new_refs: 0,
      new_refs_count: {}
    }
    query = { query: { match: { _id: git_repo } } }
    result = @es_client.search(index: 'repo', body: query)['hits']
    return fork_stat unless result['total'].positive?

    fork_stat.each_key do |key|
      fork_stat[key] = result['hits'][0]['_source'][key.to_s] || fork_stat[key]
    end
    return fork_stat
  end

  def create_year_hash(new_refs_count, year, month, day)
    new_refs_count[year] = 1
    new_refs_count[month] = 1
    new_refs_count[day] = 1
    return new_refs_count
  end

  def update_year_hash(new_refs_count, year, month, day)
    new_refs_count[year] += 1
    return create_month_hash(new_refs_count, month, day) if new_refs_count[month].nil?

    return update_month_hash(new_refs_count, month, day)
  end

  def create_month_hash(new_refs_count, month, day)
    new_refs_count[month] = 1
    new_refs_count[day] = 1

    return new_refs_count
  end

  def update_month_hash(new_refs_count, month, day)
    new_refs_count[month] += 1
    if new_refs_count[day].nil?
      new_refs_count[day] = 1
    else
      new_refs_count[day] += 1
    end
    return new_refs_count
  end

  def update_new_refs_count(new_refs_count)
    t = Time.now

    # example: 2021-01-28
    day = t.strftime('%Y-%m-%d')
    # example: 2021-01
    month = t.strftime('%Y-%m')
    # example: 2021
    year = t.strftime('%Y')
    return create_year_hash(new_refs_count, year, month, day) if new_refs_count[year].nil?

    return update_year_hash(new_refs_count, year, month, day)
  end
end

# main thread
class MirrorMain
  def merge_defaults(object_key, object)
    return object if object_key == 'default'

    defaults_key = File.dirname(object_key)
    while defaults_key != '.'
      return @defaults[defaults_key].merge(object) if @defaults[defaults_key]

      defaults_key = File.dirname(defaults_key)
    end
    return @defaults['default'].merge(object) if @defaults['default']

    return object
  end
end
