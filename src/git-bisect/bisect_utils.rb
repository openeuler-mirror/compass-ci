# frozen_string_literal: true

require 'fileutils'
require_relative './bisect_constants'

# bisect utils module
module BisectUtils
  class << self
    def clone_repo(repo)
      repo_root = "#{TMEP_GIT_BASE}/#{File.basename(repo, '.git')}-#{`echo $$`}".chomp
      FileUtils.rm_r(repo_root) if Dir.exist?(repo_root)
      system("git clone -q #{repo} #{repo_root}") ? repo_root : nil
    end

    def get_day_ago_commit(commit, day_ago, work_dir)
      date = `git -C #{work_dir} rev-list --first-parent --pretty=format:%cd \
      --date=short #{commit} -1 | sed -n 2p`.chomp!
      since = `date -d '-#{day_ago.to_i + 1} day #{date}' +%Y-%m-%d`.chomp!
      before = `date -d '1 day #{since}' +%Y-%m-%d`.chomp!
      day_ago_commit = `git -C #{work_dir} rev-list --since=#{since} --before=#{before} \
      --pretty=format:%H --first-parent #{commit} -1 | sed -n 2p`.chomp!
      return day_ago_commit
    end
  end
end
