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
require_relative 'json_logger.rb'
require 'erb'

def run_get_output(cmd)
  out = %x(#{cmd})
  code = $?.exitstatus
  STDERR.puts "Command failed: exit_code=#{code}: #{cmd}" if code != 0
  out
end

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

  def feedback(git_repo, possible_new_refs, last_commit_time)
    @feedback_info = { git_repo: git_repo, possible_new_refs: possible_new_refs, last_commit_time: last_commit_time }
    @feedback_queue.push(@feedback_info)
  end

  def get_url(url)
    if url.include?('gitee.com/') && File.exist?("/srv/git/#{url.delete_prefix('https://')}")
      url = "/srv/git/#{url.delete_prefix('https://')}"
    end
    return url
  end

  def stderr_443?(stderr_info)
    return true if stderr_info.include?('Failed to connect to github.com port 443')

    return false
  end

  def git_clone(url, mirror_dir)
    url = get_url(Array(url)[0])
    10.times do
      stderr = run_get_output("git clone -q --mirror --depth 1 #{url} #{mirror_dir}")
      return 2 if File.directory?(mirror_dir) && File.exist?("#{mirror_dir}/config")

      url = "git://#{url.split('://')[1]}" if stderr_443?(stderr)
    end
    return -2
  end

  def fetch_443(mirror_dir, fetch_info)
    return unless stderr_443?(fetch_info)

    url = run_get_output("git -C #{mirror_dir} ls-remote --get-url origin").chomp
    run_get_output("git -C #{mirror_dir} remote set-url origin git://#{url.split('://')[1]}")
  end

  def git_fetch(mirror_dir)
    if File.exist?("#{mirror_dir}/shallow")
      FileUtils.rm("#{mirror_dir}/shallow.lock") if File.exist?("#{mirror_dir}/shallow.lock")
      run_get_output("git -C #{mirror_dir} fetch --unshallow")
    end

    fetch_info = run_get_output("git -C #{mirror_dir} fetch")
    # Check whether mirror_dir is a good git repository by 2 conditions. If not, delete it.
    if fetch_info.include?(ERR_MESSAGE) && Dir.empty?(mirror_dir)
      FileUtils.rmdir(mirror_dir)
    end
    fetch_443(mirror_dir, fetch_info)
    return -1 if fetch_info.include?('fatal')

    return fetch_info.include?('->') ? 1 : 0
  end

  def url_changed?(url, mirror_dir)
    url = get_url(Array(url)[0])
    git_url = run_get_output("git -C #{mirror_dir} ls-remote --get-url origin").chomp

    return true if git_url == url || git_url.include?(url.split('://')[1])

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
    mirror_dir = "/srv/git/#{fork_info['belong']}/#{fork_info['git_repo']}"
    mirror_dir = "#{mirror_dir}.git" unless fork_info['is_submodule']
    possible_new_refs = git_repo_download(fork_info['url'], mirror_dir)
    last_commit_time = run_get_output("git -C #{mirror_dir} log --pretty=format:'%ct' -1").to_i
    feedback(fork_info['git_repo'], possible_new_refs, last_commit_time)
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
    @priority_queue = PriorityQueue.new
    @git_info = {}
    @defaults = {}
    @git_queue = Queue.new
    @log = JSONLogger.new
    @es_client = Elasticsearch::Client.new(hosts: ES_HOSTS)
    @git_mirror = GitMirror.new(@git_queue, @feedback_queue)
    clone_upstream_repo
    load_fork_info
    connection_init
    handle_webhook
    handle_pr_webhook
  end

  def connection_init
    connection = Bunny.new('amqp://172.17.0.1:5672')
    connection.start
    channel = connection.create_channel
    @message_queue = channel.queue('new_refs')
    @webhook_queue = channel.queue('web_hook')
    @webhook_pr_queue = connection.create_channel.queue('openeuler-pr-webhook')
  end

  def fork_stat_init(git_repo)
    @fork_stat[git_repo] = get_fork_stat(git_repo)
  end

  def load_defaults(defaults_file, belong)
    return unless File.exist?(defaults_file)

    repodir = File.dirname(defaults_file)
    defaults_key = repodir == "#{REPO_DIR}/#{belong}" ? belong : repodir.delete_prefix("#{REPO_DIR}/#{belong}/")
    @defaults[defaults_key] = YAML.safe_load(File.open(defaults_file))
    @defaults[defaults_key] = merge_defaults(defaults_key, @defaults[defaults_key], belong)
  end

  def traverse_repodir(repodir, belong)
    defaults_list = run_get_output("git -C #{repodir} ls-files | grep 'DEFAULTS'")
    defaults_list.each_line do |defaults|
      file = defaults.chomp
      file_path = "#{repodir}/#{file}"
      load_defaults(file_path, belong)
    end

    file_list = run_get_output("git -C #{repodir} ls-files | grep -v 'DEFAULTS'").lines
    t_list = []
    10.times do
      t_list << Thread.new do
        while file_list.length > 0
          repo = file_list.shift.chomp
          repo_path = "#{repodir}/#{repo}"
          load_repo_file(repo_path, belong)
        end
      end
    end
    t_list.each do |t|
      t.join
    end
  end

  def load_fork_info
    puts 'start load repo files !'
    @upstreams['upstreams'].each do |repo|
      traverse_repodir("#{REPO_DIR}/#{repo['location']}", repo['location'])
      puts "load #{repo['location']} repo files success !"
    end
    puts 'load ALL repo files success !!!'
  end

  def create_workers
    @worker_threads = []
    10.times do
      @worker_threads << Thread.new do
        @git_mirror.git_mirror
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

    # values of possible_new_refs:
    # 2: git clone a new repo
    # 1: git fetch and get new refs
    # 0: git fetch and no new refs
    # -1: git fetch fail
    # -2: git clone fail
    update_fork_stat(git_repo, feedback_info[:possible_new_refs])
    return if feedback_info[:possible_new_refs] < 1

    handle_feedback_new_refs(git_repo, feedback_info)
  end

  def do_push(fork_key)
    return if @fork_stat[fork_key][:queued]

    @fork_stat[fork_key][:queued] = true
    @git_info[fork_key][:cur_refs] = get_cur_refs(fork_key) if @git_info[fork_key][:cur_refs].nil?
    @git_queue.push(@git_info[fork_key])
  end

  def push_git_queue
    return if @git_queue.size >= 1
    return no_repo_warn if @priority_queue.empty?

    fork_key, old_pri = @priority_queue.delete_min
    do_push(fork_key)
    @priority_queue.push fork_key, get_repo_priority(fork_key, old_pri)
    check_worker_threads
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
  def load_repo_file(repodir, belong)
    return unless ascii_text?(repodir)

    git_repo = repodir.delete_prefix("#{REPO_DIR}/#{belong}/")
    return wrong_repo_warn(git_repo) unless git_repo =~ %r{^([a-z0-9]([a-z0-9\-_]*[a-z0-9])*(/\S+){1,2})$}

    git_info = YAML.safe_load(File.open(repodir))
    return if git_info.nil? || git_info['url'].nil? || Array(git_info['url'])[0].nil?

    if File.exist?("#{REPO_DIR}/#{belong}/erb_template") && git_info['erb_enable'] == true
      template = ERB.new File.open("#{REPO_DIR}/#{belong}/erb_template").read
      git_info = YAML.safe_load(template.result(binding))
    end

    git_info['git_repo'] = git_repo
    git_info['belong'] = belong
    git_info = merge_defaults(git_repo, git_info, belong)
    @git_info[git_repo] = git_info

    fork_stat_init(git_repo)
    @priority_queue.push git_repo, get_repo_priority(git_repo, 0)
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

    mirror_dir = "/srv/git/#{@git_info[git_repo]['belong']}/#{git_repo}.git"
    show_ref_out = run_get_output("git -C #{mirror_dir} show-ref --heads")
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

  def get_change_files(upstream_repos)
    old_commit = @git_info[upstream_repos][:cur_refs][:heads]['refs/heads/master']
    new_refs = check_new_refs(upstream_repos)
    new_commit = new_refs[:heads]['refs/heads/master']
    mirror_dir = "/srv/git/#{@git_info[upstream_repos]['belong']}/#{upstream_repos}.git"
    run_get_output("git -C #{mirror_dir} diff --name-only #{old_commit}...#{new_commit}")
  end

  def reload_fork_info(upstream_repos)
    if @git_info[upstream_repos][:cur_refs].empty?
      @git_info[upstream_repos][:cur_refs] = get_cur_refs(upstream_repos)
    else
      changed_files = get_change_files(upstream_repos)
      reload(changed_files, @git_info[upstream_repos]['belong'])
    end
  end

  def reload(file_list, belong)
    system("git -C #{REPO_DIR}/#{belong} pull")
    reload_defaults(file_list, belong)
    file_list.each_line do |file|
      file = file.chomp
      next if File.basename(file) == '.ignore' || File.basename(file) == 'DEFAULTS'

      repo_dir = "#{REPO_DIR}/#{belong}/#{file}"
      load_repo_file(repo_dir, belong) if File.file?(repo_dir)
    end
  end

  def es_repo_update(git_repo)
    repo_info = { 'git_repo' => git_repo, 'url' => @git_info[git_repo]['url'] }
    repo_info = repo_info.merge(@fork_stat[git_repo])
    body = repo_info
    begin
      @es_client.index(index: 'repo', type: '_doc', id: git_repo, body: body)
    rescue StandardError
      puts $ERROR_INFO
      sleep 1
      retry
    end
  end

  def update_fail_count(git_repo, possible_new_refs)
    @fork_stat[git_repo][:clone_fail_cnt] += 1 if possible_new_refs == -2
    @fork_stat[git_repo][:fetch_fail_cnt] += 1 if possible_new_refs == -1
  end

  def update_stat_fetch(git_repo)
    @fork_stat[git_repo][:queued] = false
    offset_fetch = @fork_stat[git_repo][:offset_fetch]
    offset_fetch = 0 if offset_fetch >= 10
    @fork_stat[git_repo][:fetch_time][offset_fetch] = Time.now.to_s
    @fork_stat[git_repo][:offset_fetch] = offset_fetch + 1
  end

  def update_new_refs_info(git_repo, offset_new_refs)
    @fork_stat[git_repo][:new_refs_time][offset_new_refs] = Time.now.to_s
    @fork_stat[git_repo][:offset_new_refs] = offset_new_refs + 1
    @fork_stat[git_repo][:new_refs_count] = update_new_refs_count(@fork_stat[git_repo][:new_refs_count])
  end

  def update_stat_new_refs(git_repo)
    offset_new_refs = @fork_stat[git_repo][:offset_new_refs]
    offset_new_refs = 0 if offset_new_refs >= 10
    update_new_refs_info(git_repo, offset_new_refs)
  end

  def update_fork_stat(git_repo, possible_new_refs)
    update_stat_fetch(git_repo)
    update_fail_count(git_repo, possible_new_refs)
    git_fail_log(git_repo, possible_new_refs) if possible_new_refs.negative?
    update_stat_new_refs(git_repo) if possible_new_refs.positive? && last_commit_new?(git_repo)
    new_repo_log(git_repo) if possible_new_refs == 2
    es_repo_update(git_repo)
  end
end

# main thread
class MirrorMain
  def check_git_repo(git_repo, webhook_url)
    if @git_info.key?(git_repo)
      git_url = Array(@git_info[git_repo]['url'])[0]
      return git_url.gsub('compass-ci-robot@', '') == webhook_url if git_url.include?('compass-ci-robot@')

      return git_url == webhook_url
    end
    return false
  end

  # example
  # url: https://github.com/berkeley-abc/abc         git_repo: a/abc/abc
  # url: https://github.com/Siguyi/AvxToNeon         git_repo: a/AvxToNeon/Siguyi
  def get_git_repo(webhook_url)
    return webhook_url.split(':')[1].gsub(' ', '') if webhook_url =~ /^(git_repo:)/

    fork_name, project = webhook_url.split('/')[-2, 2]

    git_repo = "#{project[0].downcase}/#{project}/#{fork_name}"
    return git_repo if check_git_repo(git_repo, webhook_url)

    if repo_load_fail?(git_repo)
      return git_repo if check_git_repo(git_repo, webhook_url)
    end

    git_repo = "#{project[0].downcase}/#{project}/#{project}"
    return git_repo if check_git_repo(git_repo, webhook_url)

    if repo_load_fail?(git_repo)
      return git_repo if check_git_repo(git_repo, webhook_url)
    end

    puts "webhook: #{webhook_url} is not found!"
  end

  def repo_load_fail?(git_repo)
    @upstreams['upstreams'].each do |repo|
      file_path = "#{REPO_DIR}/#{repo['location']}/#{git_repo}"
      if File.exist?(file_path)
        load_repo_file(file_path, repo['location'])
        return true
      end
    end
    return false
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

  def handle_pr_webhook
    Thread.new do
      @webhook_pr_queue.subscribe(block: true) do |_delivery, _properties, msg|
        msg = JSON.parse(msg)
        git_repo = get_git_repo(msg['url'])
        next unless git_repo

        mirror_dir = "/srv/git/#{@git_info[git_repo]['belong']}/#{git_repo}.git"
        @git_mirror.git_fetch(mirror_dir)

        update_pr_msg(msg, git_repo)
        @message_queue.publish(msg.to_json)
        sleep 0.1
      end
    end
  end

  def update_pr_msg(msg, git_repo)
    @git_info[git_repo].each do |k, v|
      msg[k] = JSON.parse(v.to_json)
    end
    return unless msg['submit_command']

    msg['submit_command'].each do |k, v|
      msg['submit'].each_index do |t|
        msg['submit'][t]['command'] += " #{k}=#{v}"
        msg['submit'][t]['command'] += " rpm_name=#{git_repo.split('/')[-1]}"
      end
    end
  end

  def handle_submodule(submodule, belong)
    submodule.each_line do |line|
      next unless line.include?('url = ')

      url = line.split(' = ')[1].chomp
      git_repo = url.split('://')[1] if url.include?('://')
      break unless git_repo

      @git_info[git_repo] = { 'url' => url, 'git_repo' => git_repo, 'is_submodule' => true, 'belong' => belong }
      fork_stat_init(git_repo)
      @priority_queue.push git_repo, get_repo_priority(git_repo, 0)
    end
  end

  def check_submodule(git_repo)
    if @git_info[git_repo]['is_submodule']
      @fork_stat[git_repo][:queued] = false
      return true
    end

    mirror_dir = "/srv/git/#{@git_info[git_repo]['belong']}/#{git_repo}.git"
    submodule = %x(git -C #{mirror_dir} show HEAD:.gitmodules 2>/dev/null)
    return if submodule.empty?

    handle_submodule(submodule, @git_info[git_repo]['belong'])
  end

  def get_fork_stat(git_repo)
    fork_stat = {
      queued: false,
      fetch_fail_cnt: 0,
      clone_fail_cnt: 0,
      fetch_time: [],
      offset_fetch: 0,
      new_refs_time: [],
      offset_new_refs: 0,
      new_refs_count: {},
      last_commit_time: 0
    }
    query = { query: { match: { _id: git_repo } } }
    return fork_stat unless @es_client.count(index: 'repo', body: query)['count'].positive?

    begin
      result = @es_client.search(index: 'repo', body: query)['hits']
    rescue StandardError
      puts $ERROR_INFO
      sleep 1
      retry
    end

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
  STEP_SECONDS = 2592000

  def handle_feedback_new_refs(git_repo, feedback_info)
    return reload_fork_info(git_repo) if upstream_repo?(git_repo)

    return handle_community_sig(git_repo) if community?(git_repo)

    new_refs = check_new_refs(git_repo)
    return if new_refs[:heads].empty?

    feedback_info[:new_refs] = new_refs
    send_message(feedback_info)
    new_refs_log(git_repo, new_refs[:heads].length) if last_commit_new?(git_repo)
  end

  def merge_defaults(object_key, object, belong)
    return object if object_key == belong

    defaults_key = File.dirname(object_key)
    while defaults_key != '.'
      return @defaults[defaults_key].merge(object) if @defaults[defaults_key]

      defaults_key = File.dirname(defaults_key)
    end
    return @defaults[belong].merge(object) if @defaults[belong]

    return object
  end

  def clone_upstream_repo
    if File.exist?('/etc/compass-ci/defaults/upstream-config')
      @upstreams = YAML.safe_load(File.open('/etc/compass-ci/defaults/upstream-config'))
      @upstreams['upstreams'].each do |repo|
        url = get_url(repo['url'])
        run_get_output("git clone -q #{url} #{REPO_DIR}/#{repo['location']}")
      end
    else
      puts 'ERROR: No upstream-config file'
      return -1
    end
  end

  def get_url(url)
    if url.include?('gitee.com/') && File.exist?("/srv/git/#{url.delete_prefix('https://')}")
      url = "/srv/git/#{url.delete_prefix('https://')}"
    end
    return url
  end

  def upstream_repo?(git_repo)
    @upstreams['upstreams'].each do |repo|
      return true if git_repo == repo['git_repo']
    end
    return false
  end

  def community?(git_repo)
    return true if git_repo == "c/community/community"
    return false
  end

  def handle_community_sig(git_repo)
    change_files = get_change_files(git_repo)
    change_files.each_line do |line|
      next unless line =~ %r{^sig/(\S+)/src-openeuler/(\S+)yaml$}

      add_openeuler_repo(line.chomp, git_repo)
    end
  end

  def add_openeuler_repo(yaml_file, git_repo)
    name = run_get_output("git -C /srv/git/openeuler/#{git_repo}.git show HEAD:#{yaml_file}").lines[0].chomp.gsub('name: ','')
    first_letter = name.downcase.chars.first
    repo_path = "#{REPO_DIR}/openeuler/#{first_letter}/#{name}"

    FileUtils.mkdir_p(repo_path, mode: 0o775)
    File.open("#{repo_path}/#{name}", 'w') do |f|
      f.write({ 'url' => Array("https://gitee.com/src-openeuler/#{name}") }.to_yaml)
    end

    run_get_output("git -C #{REPO_DIR}/openeuler add #{first_letter}/#{name}/#{name}")
    run_get_output("git -C #{REPO_DIR}/openeuler commit -m 'add repo src-openeuler/#{name}'")
    run_get_output("git -C #{REPO_DIR}/openeuler push")

    load_repo_file("#{repo_path}/#{name}", "openeuler")
    do_push("#{first_letter}/#{name}/#{name}")
  end

  def reload_defaults(file_list, belong)
    file_list.each_line do |file|
      file = file.chomp
      next unless File.basename(file) == 'DEFAULTS'

      repodir = "#{REPO_DIR}/#{belong}/#{file}"
      load_defaults(repodir, belong)
      traverse_repodir(repodir, belong)
    end
  end

  def new_repo_log(git_repo)
    @log.info({
                msg: 'new repo',
                repo: git_repo
              })
  end

  def git_fail_log(git_repo, possible_new_refs)
    msg = possible_new_refs == -1 ? 'git fetch fail' : 'git clone fail'
    @log.info({
                msg: msg,
                repo: git_repo
              })
  end

  def new_refs_log(git_repo, nr_new_branch)
    @log.info({
                msg: 'new refs',
                repo: git_repo,
                nr_new_branch: nr_new_branch
              })
  end

  def worker_threads_warn(alive)
    @log.warn({
                state: 'some workers died',
                alive_num: alive
              })
  end

  def worker_threads_error(alive)
    @log.error({
                 state: 'most workers died',
                 alive_num: alive
               })
  end

  def wrong_repo_warn(git_repo)
    @log.warn({
                msg: 'wrong repos',
                repo: git_repo
              })
  end

  def no_repo_warn
    @log.warn({
                msg: 'no repo files'
              })
  end

  def last_commit_new?(git_repo)
    inactive_time = run_get_output("git -C /srv/git/#{@git_info[git_repo]['belong']}/#{git_repo}.git log --pretty=format:'%cr' -1")
    return false if inactive_time =~ /(day|week|month|year)/

    return true
  end

  def get_repo_priority(git_repo, old_pri)
    old_pri ||= 0
    mirror_dir = "/srv/git/#{@git_info[git_repo]['belong']}/#{git_repo}"
    mirror_dir = "#{mirror_dir}.git" unless @git_info[git_repo]['is_submodule']

    step = (@fork_stat[git_repo][:clone_fail_cnt] + 1) * Math.cbrt(STEP_SECONDS)
    return old_pri + step unless File.directory?(mirror_dir)

    return cal_priority(mirror_dir, old_pri, git_repo)
  end

  def cal_priority(_mirror_dir, old_pri, git_repo)
    last_commit_time = @fork_stat[git_repo][:last_commit_time]
    step = (@fork_stat[git_repo][:fetch_fail_cnt] + 1) * Math.cbrt(STEP_SECONDS)
    return old_pri + step if last_commit_time.zero?

    t = Time.now.to_i
    interval = t - last_commit_time
    return old_pri + step if interval <= 0

    return old_pri + Math.cbrt(interval)
  end

  def check_worker_threads
    alive = 0
    @worker_threads.each do |t|
      alive += 1 if t.alive?
    end
    num = @worker_threads.size
    return worker_threads_error(alive) if alive < num / 2
    return worker_threads_warn(alive) if alive < num
  end
end

# main thread
class MirrorMain
  def ascii_text?(file_name)
    type = %x(file "#{file_name}").chomp.gsub("#{file_name}: ", '')
    return true if type == 'ASCII text'

    return false
  end
end
