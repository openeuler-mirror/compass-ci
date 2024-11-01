# SPDX-License-Identifier: GPL-2.0-only
# frozen_string_literal: true

LKP_SRC = ENV['LKP_SRC'] || '/c/lkp-tests'

require 'json'
require "#{LKP_SRC}/lib/stats"
require_relative './es_query'

KEYWORD = %w[
  suite
  os
  arch
  category
  job_state
  job_health
  job_stage
  tbox_group
  upstream_repo
  summary.success
  summary.any_fail
  summary.any_error
  summary.any_stderr
  summary.any_warning
].freeze

# deal jobs search from es
class ESJobs
  def initialize(es_query, my_refine = [], fields = [], stats_filter = [])
    @es_query = es_query
    @jobs = query_jobs_from_es
    @refine = my_refine
    @fields = fields
    @kpi = false
    @stats_filter = stats_filter
    @refine_jobs = []
    set_jobs_summary
  end

  def query_jobs_from_es
    es = ESQuery.new
    jobs = es.multi_field_scroll_query @es_query
    jobs.map! { |job| job['_source'] }
    return jobs
  end

  def set_job_summary(stats, job)
    summary_result = ''
    stats.each_key do |stat|
      # "stderr.linux-perf": 1,
      # "stderr.error:target_not_found:ruby-dev": 1,
      # "stderr.error:could_not_open_file/var/lib/pacman/local/ldb-#:#-#/desc:Not_a_directory": 1,
      if stat.match(/stderr\./i)
        job['summary.any_stderr'] = 1
        summary_result = 'stderr'
        next
      end

      # sum.stats.pkgbuild.mb_cache.c:warning:‘read_cache’defined-but-not-used[-Wunused-function]: 1
      # sum.stats.pkgbuild.mb_cache.c:warning:control-reaches-end-of-non-void-function[-Wreturn-type]: 1
      if stat.match(/:warning:|\.warning$/i)
        job['summary.any_warning'] = 1
        summary_result = 'warning'
      end

      # "last_state.test.iperf.exit_code.127": 1,
      # "last_state.test.cci-makepkg.exit_code.1": 1,
      # sum.stats.pkgbuild.cc1plus:error:unrecognized-command-line-option‘-Wno-unknown-warning-option’[-Werror]: 2
      if stat.match(/:error:|\.error$|\.exit_code\./i)
        job['summary.any_error'] = 1
        summary_result = 'error'
      end

      if stat.match(/\.fail$/i)
        job['summary.any_fail'] = 1
        summary_result = 'fail'
      end
    end
    return unless summary_result.empty?

    job['summary.success'] = 1
  end

  # set jobs summary fields information in place
  def set_jobs_summary
    @jobs.each do |job|
      stats = job['stats']
      next unless stats

      set_job_summary(stats, job)
    end
  end

  def get_all_metrics(jobs)
    metrics = []
    jobs.each do |job|
      stats = job['stats']
      next unless stats

      metrics.concat(stats.keys)
    end
    metrics.uniq
  end

  def initialize_result_hash(metrics)
    result = {
      'kvcount' => {},
      'raw.id' => {},
      'sum.stats' => {},
      'raw.stats' => {},
      'avg.stats' => {},
      'max.stats' => {},
      'min.stats' => {}
    }
    metrics.each { |metric| result['raw.stats'][metric] = [] }
    result
  end

  def set_default_value(result, stats, metrics)
    left_metrics = metrics - stats.keys
    left_metrics.each { |metric| result['raw.stats'][metric] }

    stats.each do |key, value|
      result['raw.stats'][key] << value
    end
  end

  def kvcount(result, job)
    KEYWORD.each do |keyword|
      next unless job[keyword]

      result['kvcount']["#{keyword}=#{job[keyword]}"] ||= 0
      result['kvcount']["#{keyword}=#{job[keyword]}"] += 1
      result['raw.id']["[#{keyword}=#{job[keyword]}]"] ||= []
      result['raw.id']["[#{keyword}=#{job[keyword]}]"] << job['id']
    end
  end

  def assemble_element(key, value, result)
    if key.end_with?('.element')
      value.each do |one_value_array|
        one_value_array.each do |element|
          result['sum.stats']["#{key}: #{element}"] ||= 0
          result['sum.stats']["#{key}: #{element}"] += 1
        end
      end
    else
      result['avg.stats'][key] = value.compact.sum / value.compact.size.to_f
      result['max.stats'][key] = value.compact.max
      result['min.stats'][key] = value.compact.min
    end
    result
  end

  def stats_count(result)
    result['raw.stats'].each do |key, value|
      next if key.end_with?('.message')

      if function_stat?(key)
        result['sum.stats'][key] = value.compact.size
      else
        result = assemble_element(key, value, result)
      end
    end
  end

  def query_jobs_state(jobs)
    metrics = get_all_metrics(jobs)
    result = initialize_result_hash(metrics)
    jobs.each do |job|
      kvcount(result, job)
      stats = job['stats']
      next unless stats

      set_default_value(result, stats, metrics)
    end

    stats_count(result)
    result
  end

  def output_yaml(prefix, result)
    result.each do |key, value|
      prefix_key = if prefix.empty?
                     key.to_s
                   else
                     "#{prefix}.#{key}"
                   end

      if value.is_a? Hash
        output_yaml(prefix_key, value)
      else
        puts "#{prefix_key}: #{value.to_json}"
      end
    end
  end

  def output
    output_yaml('', @result)
  end

  def generate_result
    if @jobs.empty?
      puts "No query result is found: #{@es_query}"
      return
    end
    @result = query_jobs_state(@jobs)
    @result['kvcount'] = @result['kvcount'].sort.to_h
    @result['raw.id'] = @result['raw.id'].sort.to_h
    @result
  end
end
