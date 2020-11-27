# frozen_string_literal: true

require_relative 'mail_client'
require_relative 'git'
require 'json'

# compose and send email for bisect result
class MailBisectResult
  def initialize(bisect_info)
    @error_id = bisect_info['error_id']
    @repo = bisect_info['repo']
    @commit_id = bisect_info['commit']
    @git_commit = GitCommit.new(@repo, @commit_id)
  end

  def create_send_email
    compose_mail
    send_mail
  end

  def compose_mail
    subject = "[Compass-CI] #{@repo}.git: bisect result"
    body = <<~BODY
    Hi #{@git_commit.author_name},

      Bisect completed for

      url: #{@git_commit.url}

      This is a bisect email from compass-ci. We met some problems when test with new commits.
      Would you help to check what happend?
      After submitting a job we noticed an error response due to the commit:

      commit: #{@commit_id[0..11]} ("#{@git_commit.subject}")
      error_id: #{@error_id}

    https://gitee.com/openeuler/compass-ci
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
