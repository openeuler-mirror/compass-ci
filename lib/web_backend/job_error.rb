# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './constants.rb'

UTC_OFFSET = Time.new.utc_offset
JOB_PAGE_URL = 'https://compass-ci.openeuler.org/jobs'

# output job errors
class JobError
  def initialize(job_list, now = Time.now)
    @job_list = job_list
    @now = now
    @today_errors = {}
    @other_errors = {}
  end

  def active_error
    @job_list.each do |job|
      start_time = job['start_time']
      if today_job?(start_time, @now)
        assign_today_errors(job, start_time)
      else
        assign_other_errors(job, start_time)
      end
    end

    jobs_errors
  end

  def assign_today_errors(job, start_time)
    job['stats'].each_key do |metric|
      error = error?(metric, job)
      next unless error

      @today_errors[error] ||= { 'count' => 0 }
      @today_errors[error]['count'] += 1
      @today_errors[error]['first_date'] = start_time
      @today_errors[error]['suite'] ||= job['suite']
      @today_errors[error]['job_owner'] ||= job['my_account']
      @today_errors[error]['relevant_links'] ||= job['result_root']
      @today_errors[error]['error_message'] = error
    end
  end

  def assign_other_errors(job, start_time)
    job['stats'].each_key do |metric|
      error = error?(metric, job)
      @other_errors[error] = start_time if error
    end
  end

  def jobs_errors
    jobs_errors = []
    @today_errors.each do |error, value|
      value['first_date'] = first_date(error, value)
      jobs_errors << value
    end

    jobs_errors.sort! { |x, y| y['count'] <=> x['count'] }
  end

  def first_date(error, value)
    fitst_date = @other_errors[error] || value['first_date']

    fitst_date.slice(0, fitst_date.index('T'))
  end
end

def error?(metric, job)
  return metric if metric.start_with?('stderr') && !metric.end_with?('has_stderr')

  if metric.end_with?('fail')
    return job[metric] || metric
  end

  nil
end

def today_job?(start_time, now)
  job_time = DateTime.parse(start_time).to_time # like: 2021-06-23 15:24:18 +0000
  return true if (now + UTC_OFFSET - job_time) < ONE_DAY_SECOND

  false
end
