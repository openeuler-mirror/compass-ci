# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'git'
require_relative 'es_query'
require_relative 'constants'
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
    @to = @git_commit.author_email
    # now send mail to review
    @bcc = 'caoxl@crystal.ci, caoxl78320@163.com, huming15@163.com, wfg@mail.ustc.edu.cn'
  end

  def create_send_email
    send_report_mail(compose_mail)
    send_account_mail
  end

  def compose_mail
    subject = "[Compass-CI][#{@repo.split('/')[1]}] #{@commit_id[0..9]} #{@bisect_error[0].split("\n")[0]}"
    prefix_srv = "http://#{SRV_HTTP_DOMAIN}:#{SRV_HTTP_PORT}"
    bisect_job_url = ENV['result_root'] ? "bisect job result directory:\n#{prefix_srv}#{ENV['result_root']}\n" : ''
    bisect_report_doc = "bisect email doc:\nhttps://gitee.com/wu_fengguang/compass-ci/blob/master/doc/bisect_email.en.md\n"
    pkgbuild_repo_url = "PKGBUILD:\n#{prefix_srv}/#{@pkgbuild_repo}\n"
    first_bad_commit_job_url = "first bad commit job result directory:\n#{prefix_srv}#{@first_bad_commit_result_root}\n"

    data = <<~BODY
    To: #{@to}
    Bcc: #{@bcc}
    Subject: #{subject}

    Hi #{@git_commit.author_name},

    We found some error/warning(s) and the first bad commit in the below project:
    git url: #{@git_commit.url}
    git commit: #{@commit_id} ("#{@git_commit.subject}")

    All error/warning(s) (new ones prefixed by >>):
    #{@all_errors}

    Reference information:
    compiler: gcc (GCC) 7.3.0
    #{pkgbuild_repo_url}
    #{first_bad_commit_job_url}
    #{bisect_job_url}
    #{bisect_report_doc}
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

    account_info = ESQuery.new(index: 'accounts').query_by_id(@to)
    return if account_info

    apply_account = AutoAssignAccount.new(user_info)
    apply_account.send_account
  end
end
