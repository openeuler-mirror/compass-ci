# frozen_string_literal: true

require 'yaml'
require 'fileutils'

# worker threads
class GitMirror
  def initialize(queue, feedback_queue)
    @queue = queue
    @feedback_queue = feedback_queue
    @feedback_info = {}
  end

  def handle_strings(strings)
    strings.each_index do |index|
      if strings[index] == 'branch'
        @feedback_info[:new_refs][:heads][strings[index + 1]] = strings.first
        return true
      elsif strings[index] == 'tag'
        @feedback_info[:new_refs][:tags][strings[index + 1]] = strings.first
        return true
      end
    end
    return false
  end

  def handle_line(line)
    strings = line.split
    ret = handle_strings(strings)
    if !ret && strings.length == 2
      @feedback_info[:new_refs][:heads][strings[1]] = strings.first
    else
      errlog = File.open('errlog', 'a')
      errlog.puts "unresolved line: #{line}\n"
    end
  end

  # FETCH_HEAD content example:
  # 3031dbcd8f9ebf702b7cc8f046cd12393cf64e5a                branch 'master' of file:///c/lkp-tests
  # b23c83df362fdcf0cfcedeae2934176ec0af3b51        not-for-merge   branch 'sunlijun' of file:///c/lkp-tests
  def feedback(has_new_refs, git_repo, content)
    @feedback_info = { git_repo: git_repo }
    if has_new_refs
      @feedback_info[:new_refs] = { heads: {}, tags: {} }
      content.each_line do |line|
        next if line.start_with? '#'

        handle_line(line)
      end
    end
    @feedback_queue.push(@feedback_info)
  end

  def fetch_read(mirror_dir)
    return File.exist?("#{mirror_dir}/FETCH_HEAD") ? File.read("#{mirror_dir}/FETCH_HEAD") : ''
  end

  def mirror_once
    fork_info = @queue.pop
    mirror_dir = "/srv/git/#{fork_info['forkdir']}.git"
    if File.directory?(mirror_dir)
      content_old = fetch_read(mirror_dir)
      system("git -C #{mirror_dir} fetch")
      content = fetch_read(mirror_dir)
      has_new_refs = (content != content_old)
    else
      FileUtils.mkdir_p(mirror_dir)
      system("git clone --bare #{fork_info['url']} #{mirror_dir}")
      content = `git show-ref --heads`
      has_new_refs = true
    end
    feedback(has_new_refs, fork_info['forkdir'], content)
  end

  def gitmirror
    loop do
      mirror_once
    end
  end
end

# main thread
class MirrorMain
  def initialize
    @feedback_queue = Queue.new
    @fork_stat = {}
    @git_info = {}
    @git_queue = SizedQueue.new(10)
    load_fork_info
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
        git_mirror.gitmirror
      end
      sleep(0.1)
    end
  end

  def fork_loop
    loop do
      @git_info.each do |key, fork_info|
        next if @fork_stat[key][:queued]

        @fork_stat[key][:queued] = true
        @git_queue.push(fork_info)
        sleep(10)
      end
    end
  end
end
