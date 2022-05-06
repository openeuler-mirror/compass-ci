# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './delimiter/delimiter'
require_relative '../lib/config_account'

def config_secrets_yaml
  account = YAML.load_file "#{ENV['HOME']}/.config/compass-ci/defaults/account.yaml"
  lab = YAML.load_file "#{ENV['HOME']}/.config/compass-ci/include/lab/#{account['lab']}.yaml"
  secrets = Hash['secrets' => lab]
  File.open("#{ENV['HOME']}/.config/compass-ci/defaults/secrets.yaml", 'w') { |f| YAML.dump(secrets, f) }
end

begin
  config_yaml('delimiter')
  config_secrets_yaml
  delimiter = Delimiter.new
  delimiter.start_delimit
rescue StandardError => e
  puts e
end
