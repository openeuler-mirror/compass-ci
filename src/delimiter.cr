# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require "yaml"
require "./delimiter/delimiter"

def config_secrets_yaml
  %x(#{ENV["CCI_SRC"]}/sbin/config_account_yaml.rb delimiter)
  account = YAML.parse(File.read("#{ENV["HOME"]}/.config/compass-ci/defaults/account.yaml"))
  lab = YAML.parse(File.read("#{ENV["HOME"]}/.config/compass-ci/include/lab/#{account["lab"]}.yaml"))
  secrets = {"secrets" => lab}
  File.open("#{ENV["HOME"]}/.config/compass-ci/defaults/secrets.yaml", "w") { |f| YAML.dump(secrets, f) }
end

begin
  config_secrets_yaml
  delimiter = Delimiter.new
  delimiter.consume_delimiter("delimiter")
rescue ex
  puts ex
end
