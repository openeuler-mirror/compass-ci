# frozen_string_literal: true

# wrap common git commands
class GitCommit
  def initialize(work_dir, commit)
    @git_prefix = "git -C #{work_dir}"
    @commit = commit
  end

  def author_name
    `#{@git_prefix} log -n1 --pretty=format:'%an' #{@commit}`.chomp
  end

  def author_email
    `#{@git_prefix} log -n1 --pretty=format:'%ae' #{@commit}`.chomp
  end

  def author_email_name
    "#{author_name} <#{author_email}>"
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
