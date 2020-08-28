# frozen_string_literal: true

require_relative 'mail_client.rb'
require 'json'

# compose and send email for bisect result
class MailBisectResult
  def initialize(bisect_info)
    @repo = bisect_info['repo']
    @commit_id = bisect_info['commit']
  end

  def create_send_email
    parse_commit_info
    compose_mail
    send_mail
  end

  def parse_commit_info
    git_prefix = "git -C /srv/git/#{@repo}.git"
    @author = `#{git_prefix} log -n1 --pretty=format:'%an' #{@commit_id}`
    @email = `#{git_prefix} log -n1 --pretty=format:'%ae' #{@commit_id}`
    @git_url = `#{git_prefix} remote -v`.split[1]
    @git_diff = `#{git_prefix} diff --stat -1 #{@commit_id}~..#{@commit_id}`
  end

  def compose_mail
    subject = "[Crystal-CI] delimit #{@repo} result for commit #{@commit_id}"
    signature = "Crystal-CI delimit service\nhttps://gitee.com/openeuler/crystal-ci"
    body = "Hi #{@author},\n\nDelimit for #{@git_url} succeeded.\n\n#{@git_diff}\n\n#{signature}"
    @hash = { 'to' => @email, 'body' => body, 'subject' => subject }
  end

  def send_mail
    json = @hash.to_json
    MailClient.new.send_mail(json)
  end
end
