# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

# ----------------------------------------------------------------------------------------------------
# format compare results for a specific format
#

def format_for_echart(metrics_compare_results, template_params)
  echart_result = {}
  echart_result['title'] = template_params['title']
  echart_result['unit'] = template_params['unit']
  x_params = template_params['x_params']
  echart_result['x_name'] = x_params.join('|') if x_params
  echart_result['tables'] = metrics_compare_results

  echart_result
end
