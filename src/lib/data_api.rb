# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

CCI_SRC ||= ENV['CCI_SRC'] || '/c/compass-ci'
require "#{CCI_SRC}/lib/json_logger.rb"
require "#{CCI_SRC}/src/lib/data_api/es_data_api.rb"

def check_xss(params)
  raise 'please input valid params' if params.match? /[^\w\"\'\+\{\}\[\]\.\_\,\ \:\/\-\;\%\=\<\>]/
end

def es_search(index, params)
  begin
    check_xss(params)
    result = EsDataApi.search(index, params)
  rescue StandardError => e
    error_msg = { 'error_msg' => e.message }
    log_error(error_msg)
    return [200, headers.merge('Access-Control-Allow-Origin' => '*'), error_msg.to_json]
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result.to_json]
end

def es_opendistro_sql(params)
  begin
    result = EsDataApi.opendistro_sql(params)
  rescue StandardError => e
    error_msg = { 'error_msg' => e.message }
    log_error(error_msg)
    return [200, headers.merge('Access-Control-Allow-Origin' => '*'), error_msg.to_json]
  end
  [200, headers.merge('Access-Control-Allow-Origin' => '*'), result.to_json]
end
