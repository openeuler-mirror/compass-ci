# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

def locate_files(data)
  result = {}

  data.each do |key, value|
    temp = []
    value.each do |val|
      val = val.strip
      temp << File.realpath(val) if File.exist?(val)
    end

    result.merge!({ "#{key}": temp })
  end

  return result
end
