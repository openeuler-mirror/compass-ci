# frozen_string_literal: true

require_relative 'mail_client'
require_relative 'git'
require 'json'

# compose and send email for bisect result
class MailBisectResult
  def initialize(bisect_info)
    @error_messages = bisect_info['error_messages']
    @repo = bisect_info['repo']
    @commit_id = bisect_info['commit']
    @git_commit = GitCommit.new(@repo, @commit_id)
  end

  def create_send_email
    compose_mail
    send_mail
  end

  def compose_mail
    subject = "[Compass-CI][#{@repo.split('/')[1]}]: #{@error_messages[0]}"
    job_url = "job url: #{ENV['SRV_HTTP_HOST']}:#{ENV['SRV_HTTP_PORT']}/#{ENV['result_root']}\n" ? ENV['result_root'] : ''
    body = <<~BODY
    Hi #{@git_commit.author_name},

      git url: #{@git_commit.url}
      git commit: #{@commit_id[0..11]} ("#{@git_commit.subject}")

      gcc version: 7.3.0
      error_messages:
      #{@error_messages.join("\n")}

      #{job_url}
    Regards,
    Compass CI team
    BODY
    to = 'caoxl@crystal.ci'
    @hash = { 'to' => to, 'body' => body, 'subject' => subject }
    # @hash = { 'to' => @git_commit.author_email, 'body' => body, 'subject' => subject }
  end

  def send_mail
    json = @hash.to_json
    MailClient.new.send_mail(json)
  end
end
