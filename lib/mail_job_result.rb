# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require_relative 'mail_client.rb'
require_relative 'es_query.rb'
require_relative 'constants.rb'
require 'json'

# compose and send email for job result
class MailJobResult
  def initialize(job_id)
    @job_id = job_id
  end

  def send_mail
    json = compose_mail.to_json
    MailClient.new.send_mail(json)
  end

  def compose_mail
    set_submitter_info
    subject = "[Crystal-ci] job: #{@job_id} result"
    signature = "Regards\nCrystal-ci\nhttps://gitee.com/openeuler/crystal-ci"
    body = "Hi,
    Thanks for your participation in Kunpeng and software ecosystem!
    Your Job: #{@job_id} had finished.
    Please check job result: \n\n#{signature}"
    { 'to' => @submitter_email, 'body' => body, 'subject' => subject }
  end

  def set_submitter_info
    job = query_job
    exit unless job['email']

    @submitter_email = job['email']
  end

  def query_job
    es = ESQuery.new
    query_result = es.multi_field_query({ 'id' => @job_id })
    query_result['hits']['hits'][0]['_source']
  end
end
