# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative 'mail_client.rb'
require_relative 'es_query.rb'
require_relative 'compare.rb'
require_relative 'constants.rb'
require 'json'

# compose and send email for job result
class MailJobResult
  def initialize(upstream_commit, result_host = SRV_HTTP_RESULT_HOST, result_port = SRV_HTTP_RESULT_PORT)
    @upstream_commit = upstream_commit
    @result_host = result_host
    @result_port = result_port
  end

  def send_mail
    data = compose_mail
    return nil unless data
    MailClient.new.send_mail_encode(data)
  end

  def compose_mail
    set_submitter_info
    context = keep_100_lines(get_compare_result(@job))
    return nil unless context

    subject = "[Compass-CI] #{@job['commit_title'] || @job['id']} comparsion"
    signature = "Regards\nCompass-CI\nhttps://gitee.com/openeuler/compass-ci"

    data = <<~BODY
    To: #{@email_to}
    Bcc: #{@email_cc}
    Subject: #{subject}

    Hi,

    Thanks for your participation in Kunpeng and software ecosystem!
    Bellow are comparsion result of the base commit and your commit:
    \tbase commit: #{@job['base_commit']}
    \tcommit_link: #{@job['upstream_url']}/commit/#{@job['base_commit']}

    \tyour commit: #{@job['upstream_commit']}
    \tbranch: #{@job['upstream_branch']}
    \tcommit_link: #{@job['upstream_url']}/commit/#{@job['upstream_commit']}

    compare command:
    \tcompare upstream_commit=#{@job['base_commit']}  upstream_commit=#{@job['upstream_commit']} --min_samples #{@job['nr_run']}
    #{context.to_s}
    \n\n#{signature}
    BODY

    data
  end

  def set_submitter_info
    sleep 10
    @job = query_job
    exit unless @job && @job['author_email']

    @email_to = @job['author_email']
    @email_cc = @job['committer_email']
    @result_root = @job['result_root']
  end

  def query_job
    es = ESQuery.new
    query_result = es.multi_field_query({ 'upstream_commit' => @upstream_commit })
    if query_result['hits']['hits'].empty?
      warn "Non-existent jobs"
      return nil
    end

    query_result['hits']['hits'][0]['_source']
  end
end

def get_compare_result(job)
  min_samples = job['nr_num'].to_i
  base_commit = job['base_commit']
  commit_id = job['upstream_commit']
  return nil unless base_commit && commit_id

  condition_list = [{'upstream_commit' => base_commit}, {'upstream_commit' => commit_id}]
  options = { :min_samples => min_samples, :no_print => true}

  matrices_list, suite_list = create_matrices_list(condition_list, options[:min_samples])
  return nil if matrices_list.size < 2

  m_titles = [base_commit.slice(0, 16), commit_id.slice(0, 24)]
  compare_matrixes(matrices_list, suite_list, nil, m_titles, options: options)
end

def keep_100_lines(context)
  context.split("\n")[0,99].join("\n")
end
