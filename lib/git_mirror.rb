# frozen_string_literal: true

require 'yaml'
require 'fileutils'

# worker threads
class GitMirror
  def initialize(queue)
    @queue = queue
  end

  def mirror_once
    fork_info = @queue.pop
    mirror_dir = '/srv/git/' + fork_info['forkdir'] + '.git'
    if File.directory?(mirror_dir)
      system("git -C #{mirror_dir} fetch")
    else
      FileUtils.mkdir_p(mirror_dir)
      system("git clone --bare #{fork_info['url']} #{mirror_dir}")
    end
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
    @git_info = {}
    @git_queue = SizedQueue.new(10)
    load_fork_info
  end

  attr_reader :git_info
  attr_reader :git_queue

  def load_fork_info
    repodir = "#{ENV['LKP_SRC']}/repo"
    project_list = Dir.entries(repodir) - Array['.', '..']
    project_list.each do |project|
      project_dir = "#{repodir}/#{project}"
      fork_list = Dir.entries(project_dir) - Array['.', '..', 'DEFAULTS', '.ignore']
      fork_list = Array['linus'] if project == 'linux'
      fork_list.each do |fork_name|
        @git_info["#{project}/#{fork_name}"] = YAML.safe_load(File.open("#{project_dir}/#{fork_name}"))
        @git_info["#{project}/#{fork_name}"]['forkdir'] = "#{project}/#{fork_name}"
      end
    end
  end

  def create_workers
    10.times do
      Thread.new do
        git_mirror = GitMirror.new(@git_queue)
        git_mirror.gitmirror
      end
      sleep(0.1)
    end
  end

  def fork_loop
    loop do
      @git_info.each do |_key, value|
        fork_info = value
        @git_queue.push(fork_info)
        sleep(10)
      end
    end
  end
end
