# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'git'
require_relative 'mail_client'
require_relative 'assign_account_client'

# compose and send email for bisect result
class MailBisectResult
  def initialize(bisect_info)
    @repo = bisect_info['repo']
    @commit_id = bisect_info['commit']
    @all_errors = bisect_info['all_errors']
    @bisect_error = bisect_info['bisect_error']
    @pkgbuild_repo = bisect_info['pkgbuild_repo']
    @first_bad_commit_result_root = bisect_info['first_bad_commit_result_root']
    @git_commit = GitCommit.new(@repo, @commit_id)
    # now send mail to review
    @to = 'caoxl@crystal.ci, caoxl78320@163.com, huming15@163.com'
  end

  def create_send_email
    send_report_mail(compose_mail)
    send_account_mail
  end

  def compose_mail
    subject = "[Compass-CI][#{@repo.split('/')[1]}] #{@commit_id[0..9]} #{@bisect_error[0].split("\n")[0]}"
    prefix_srv = "http://#{ENV['SRV_HTTP_HOST']}:#{ENV['SRV_HTTP_PORT']}"
    bisect_job_url = ENV['result_root'] ? "bisect job info: #{prefix_srv}#{ENV['result_root']}\n" : ''
    pkgbuild_repo_url = "PKGBUILD info: #{prefix_srv}/#{@pkgbuild_repo}\n"
    first_bad_commit_job_url = "first bad commit job info: #{prefix_srv}#{@first_bad_commit_result_root}\n"

    data = <<~BODY
    To: #{@to}
    Subject: #{subject}

    Hi #{@git_commit.author_name},

    url: #{@git_commit.url}
    commit: #{@commit_id} ("#{@git_commit.subject}")
    compiler: gcc (GCC) 7.3.0

    all errors/warnings (new ones prefixed by >>):
    #{@all_errors}

    reference information:
    #{pkgbuild_repo_url}
    #{bisect_job_url}
    #{first_bad_commit_job_url}
    Regards,
    Compass CI team
    BODY

    return data
  end

  def send_report_mail(mail_data)
    MailClient.new.send_mail_encode(mail_data)
  end

  def send_account_mail
    user_info = {
      'my_email' => @to,
      'my_name' => @git_commit.author_name,
      'my_commit_url' => "#{@git_commit.url}/commit/#{@commit_id}"
    }

    apply_account = AutoAssignAccount.new(user_info)
    apply_account.send_account
  end
end
