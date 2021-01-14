# SPDX-License-Identifier: GPL-2.0-only
# frozen_string_literal: true

LKP_SRC = ENV['LKP_SRC'] || '/c/lkp-tests'

require "#{LKP_SRC}/lib/stats"
require_relative './es_query'

# deal jobs search from es
class ESJobs
  def initialize(es_query, my_refine = [], fields = [], stats_filter = [])
    @es_query = es_query
    @es = ESQuery.new(ES_HOST, ES_PORT)
    @refine = my_refine
    @fields = fields
    @stats_filter = stats_filter
    @stats_filter_result = {}
    @refine_jobs = []
    @jobs = {}
    @stats_level = {
      0 => 'stats.success',
      1 => 'stats.unknown',
      2 => 'stats.warning',
      3 => 'stats.has_error'
    }
    set_defaults
    deal_jobs
  end

  def set_defaults
    query_result = @es.multi_field_query(@es_query)
    query_result['hits']['hits'].each do |job|
      @jobs[job['_id']] = job['_source']
    end

    @stats = {
      'stats.count' => Hash.new(0),
      'stats.sum' => Hash.new(0),
      'stats.avg' => Hash.new(0)
    }
    @result = {}
    @fields.each do |field|
      @result[field] = []
    end
  end

  def add_result_fields(job, level)
    return unless @refine.include?(level) || @refine.include?(-1)

    @refine_jobs << job['id']
    @fields.each do |field|
      value = job[field]
      if value
        value = job['id'] + '.' + value if field == 'job_state'
        @result[field] << value
      end

      next unless job['stats']

      @result[field] << job['stats'][field] if job['stats'][field]
    end
  end

  def deal_jobs
    stats_count = Hash.new(0)
    stats_jobs = {}

    @jobs.each do |job_id, job|
      level = deal_stats(job)
      add_result_fields(job, level)

      stat_key = @stats_level[level]
      stat_jobs_key = stat_key + '_jobs'

      stats_count[stat_key] += 1
      stats_jobs[stat_jobs_key] ||= []
      stats_jobs[stat_jobs_key] << job_id
    end

    @stats['stats.count'].merge!(stats_count)
    @stats['stats.count'].merge!(stats_jobs)
  end

  def deal_stats(job, level = 0)
    return 1 unless job['stats']

    job['stats'].each do |key, value|
      match_stats_filter(key, value, job['id'])
      calculate_stat(key, value)
      level = get_stat_level(key, level)
    end
    return level
  end

  def match_stats_filter(key, value, job_id)
    @stats_filter.each do |filter|
      next unless key.include?(filter)

      key = job_id + '.' + key
      @stats_filter_result[key] = value

      break
    end
  end

  def calculate_stat(key, value)
    if function_stat?(key)
      return unless @fields.include?('stats.sum')

      @stats['stats.sum'][key] += value
    else
      return unless @fields.include?('stats.avg')

      @stats['stats.avg'][key] = (@stats['stats.avg'][key] + value) / 2
    end
  end

  def get_stat_level(stat, level)
    return level if level >= 3
    return 3 if stat.match(/error|fail/i)
    return 2 if stat.match(/warn/i)

    return 0
  end

  def output
    result = {
      'stats.count' => @stats['stats.count']
    }

    @stats.each do |key, value|
      result[key] = value if @fields.include?(key)
    end

    @result['stats_filter_result'] = @stats_filter_result unless @stats_filter.empty?
    @result.merge!(result)
    puts JSON.pretty_generate(@result)
  end
end
