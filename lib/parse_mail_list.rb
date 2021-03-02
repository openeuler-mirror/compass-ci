# SPDX-License-Identifier: MulanPSL-2.0+
# frozen_string_literal: true

require 'yaml'

def parse_mail_list(type)
  content = {}
  mail_list_yaml = '/etc/compass-ci/report-email.yaml'
  content = YAML.safe_load(File.open(mail_list_yaml)) if FileTest.exists?(mail_list_yaml)

  return content[type] || {}
end
