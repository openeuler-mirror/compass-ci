# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'git'
require_relative 'es_query'
require_relative 'constants'
require_relative 'mail_client'
require_relative 'assistant_client'
require_relative 'assign_account_client'

# compose and send email for bisect result
class MailBisectResult
  def initialize(bisect_info)
    @repo = bisect_info['repo']
    @work_dir = bisect_info['work_dir']
    @commit_id = bisect_info['commit']
    @all_errors = bisect_info['all_errors']
    @bisect_error = bisect_info['bisect_error']
    @upstream_url = bisect_info['upstream_url']
    @pkgbuild_repo = bisect_info['pkgbuild_repo']
    @first_bad_commit_result_root = bisect_info['first_bad_commit_result_root']
    @git_commit = GitCommit.new(@work_dir, @commit_id)
    @to = @git_commit.author_email
    @rto = @git_commit.author_email
  end

  def parse_mail_info
    mail_hash = AssistantClient.new.get_mail_list('delimiter')
    @to = mail_hash['to'] if mail_hash.key?('to')
    @bcc = mail_hash['bcc'] if mail_hash.key?('bcc')
    raise 'Need to add bcc email for bisect report.' unless @bcc
  end

  def create_send_email
    parse_mail_info
    send_report_mail(compose_mail)
    send_account_mail
    rm_work_dir
  end

  def compose_mail
    subject = "[Compass-CI][#{@repo.split('/')[1]}] #{@commit_id[0..9]} #{@bisect_error[0].split("\n")[0]}"
    prefix_srv_result = "http://#{SRV_HTTP_DOMAIN}:#{SRV_HTTP_RESULT_PORT}"
    prefix_srv_git = "http://#{SRV_HTTP_DOMAIN}:#{SRV_HTTP_GIT_PORT}"
    pkgbuild_repo_url = "we build project with this script:\n#{prefix_srv_git}/git/#{@pkgbuild_repo}/PKGBUILD\n"
    first_bad_commit_job_url = "first bad commit result :\n#{prefix_srv_result}#{@first_bad_commit_result_root}/build-pkg\n"

    data = <<~BODY
    To: #{@to}
    Bcc: #{@bcc}
    Subject: #{subject}

    Hi #{@git_commit.author_name},

    Some error/warning(s) are found in
    git url: #{@upstream_url}/commit/#{@commit_id}
    git commit: #{@commit_id} ("#{@git_commit.subject}")
    git commit author email: #{@rto}

    All error/warning(s) (new ones prefixed by >>):
    #{@all_errors}

    Reference information:
    compiler: gcc (GCC) 7.3.0
    #{pkgbuild_repo_url}
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
      'my_email' => @rto,
      'my_name' => @git_commit.author_name,
      'my_commit_url' => "#{@git_commit.url}/commit/#{@commit_id}"
    }
    AssistantClient.new.send_account_mail(user_info)
  end

  def rm_work_dir
    FileUtils.rm_r(@work_dir) if Dir.exist?(@work_dir)
  end
end
