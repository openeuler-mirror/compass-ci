# frozen_string_literal: true

# wrap common git commands
class GitCommit
  def initialize(repo, commit)
    @git_prefix = "git -C /srv/git/#{repo}.git"
    @commit = commit
  end

  def author_name
    `#{@git_prefix} log -n1 --pretty=format:'%an' #{@commit}`.chomp
  end

  def author_email
    `#{@git_prefix} log -n1 --pretty=format:'%ae' #{@commit}`.chomp
  end

  def subject
    `#{@git_prefix} log -n1 --pretty=format:'%s' #{@commit}`.chomp
  end

  def commit_time
    `#{@git_prefix} log -n1 --pretty=format:'%ci' #{@commit}`.chomp
  end

  def url
    `#{@git_prefix} remote -v`.split[1]
  end

  def diff
    `#{@git_prefix} diff -1 #{@commit}~..#{@commit}`.chomp
  end
end
