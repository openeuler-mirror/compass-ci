# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# ----------------------------------------------------------------------------------------------------
# format compare results for a specific format
#
class FormatEchartData
  def initialize(metrics_compare_results, template_params)
    @metrics_compare_results = metrics_compare_results
    @template_params = template_params
    @data_set = {}
  end

  def format_for_echart
    echart_result = {}
    echart_result['title'] = @template_params['title']
    echart_result['unit'] = @template_params['unit']
    @x_name = @template_params['x_params']
    echart_result['x_name'] = @x_name.join('|') if @x_name
    echart_result['tables'] = convert_to_echart_dataset

    echart_result
  end

  def convert_to_echart_dataset
    @x_params = sort_x_params(@metrics_compare_results.keys)
    @metrics_compare_results.each_value do |metrics_values|
      metrics_values.each do |metric, metric_value|
        assign_echart_data_set(metric, metric_value)
      end
    end

    @data_set
  end

  def assign_echart_data_set(metric, metric_value)
    @data_set[metric] = {}
    metric_value.each do |value_type, values| # value_type can be: average, standard_deviation, change
      @data_set[metric][value_type] = {
        'dimensions' => ['compare_dimension']
      }

      dimension_list = values.keys.sort
      @data_set[metric][value_type]['dimensions'] += dimension_list
      @data_set[metric][value_type]['source'] = assign_echart_source(metric, value_type, dimension_list)
    end
  end

  def assign_echart_source(metric, value_type, dimensions)
    source = []
    source << @x_params
    dimensions.each do |dimension|
      dimension_values = [dimension]
      @x_params.each do |x_param|
        if @metrics_compare_results[x_param][metric]
          dimension_values << @metrics_compare_results[x_param][metric][value_type][dimension]
        end
      end
      source << dimension_values
    end

    source
  end
end

# input: x_params_list
# eg: ["1G|4K", "1G|1024k", "1G|128k", 2G|4k]
# output:
# ["1G|4K", "1G|128k", "1G|1024k", "2G|4k"]
def sort_x_params(x_params_list)
  x_params_hash = {}
  x_params_list.each do |param|
    params = param.gsub(/[a-zA-Z]+$/, '').split('|').map(&:to_i)
    x_params_hash[params] = param
  end

  x_params_hash.sort.map { |h| h[1] }
end
