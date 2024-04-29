# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require 'set'
require_relative 'decrypt.rb'
require_relative '../container/defconfig.rb'

config = cci_defaults
decrypt_dict = decrypt_text_from_env

names = Set.new %w[
  ES_USER
  ES_PASSWORD
  LOGGING_ES_USER
  LOGGING_ES_PASSWORD
]

ES_HOST ||= ENV['ES_HOST'] || config['ES_HOST'] || '172.17.0.1'
ES_PORT ||= ENV['ES_PORT'] || config['ES_PORT'] || 9200

LOGGING_ES_HOST ||= ENV['LOGGING_ES_HOST'] || config['LOGGING_ES_HOST'] || '172.17.0.1'
LOGGING_ES_PORT ||= ENV['LOGGING_ES_PORT'] || config['LOGGING_ES_PORT'] || 9202

if ENV['ES_USER']
  ES_USER = ENV['ES_USER']
  ES_PASSWORD = ENV['ES_PASSWORD']
elsif decrypt_dict['ES_USER']
  ES_USER = decrypt_dict['ES_USER']
  ES_PASSWORD = decrypt_dict['ES_PASSWORD']
else
  service_authentication = relevant_service_authentication(names)
  ES_USER = service_authentication['ES_USER']
  ES_PASSWORD = service_authentication['ES_PASSWORD']
end

ES_HOSTS = [{
  host: ES_HOST,
  port: ES_PORT,
  user: ES_USER,
  password: ES_PASSWORD
}].freeze

if ENV['LOGGING_ES_USER']
  LOGGING_ES_USER = ENV['LOGGING_ES_USER']
  LOGGING_ES_PASSWORD = ENV['LOGGING_ES_PASSWORD']
elsif decrypt_dict['LOGGING_ES_USER']
  LOGGING_ES_USER = decrypt_dict['LOGGING_ES_USER']
  LOGGING_ES_PASSWORD = decrypt_dict['LOGGING_ES_PASSWORD']
else
  service_authentication = relevant_service_authentication(names)
  LOGGING_ES_USER = service_authentication['LOGGING_ES_USER']
  LOGGING_ES_PASSWORD = service_authentication['LOGGING_ES_PASSWORD']
end

LOGGING_ES_HOSTS = [{
  host: LOGGING_ES_HOST,
  port: LOGGING_ES_PORT,
  user: LOGGING_ES_USER,
  password: LOGGING_ES_PASSWORD
}].freeze

KIBANA_HOST ||= config['KIBANA_HOST'] || '172.17.0.1'
KIBANA_PORT ||= config['KIBANA_PORT'] || '20017'

LOGGING_KIBANA_HOST ||= config['LOGGING_KIBANA_HOST'] || '172.17.0.1'
LOGGING_KIBANA_PORT ||= config['LOGGING_KIBANA_PORT'] || '20000'

SEND_MAIL_HOST ||= config['SEND_MAIL_HOST'] || '172.17.0.1'
SEND_MAIL_PORT ||= config['SEND_MAIL_PORT'] || 10001

LOCAL_SEND_MAIL_HOST ||= config['LOCAL_SEND_MAIL_HOST'] || '172.17.0.1'
LOCAL_SEND_MAIL_PORT ||= config['LOCAL_SEND_MAIL_PORT'] || 11311

SRV_HTTP_RESULT_HOST ||= config['SRV_HTTP_RESULT_HOST'] || ENV['SRV_HTTP_RESULT_HOST'] || '172.17.0.1'
SRV_HTTP_OS_HOST ||= config['SRV_HTTP_OS_HOST'] || ENV['SRV_HTTP_OS_HOST'] || '172.17.0.1'
SRV_HTTP_GIT_HOST ||= config['SRV_HTTP_GIT_HOST'] || ENV['SRV_HTTP_GIT_HOST'] || '172.17.0.1'
SRV_HTTP_RESULT_PORT ||= config['SRV_HTTP_RESULT_PORT'] || ENV['SRV_HTTP_RESULT_PORT'] || 20007
SRV_HTTP_OS_PORT ||= config['SRV_HTTP_OS_PORT'] || ENV['SRV_HTTP_OS_PORT'] || 20009
SRV_HTTP_GIT_PORT ||= config['SRV_HTTP_GIT_PORT'] || ENV['SRV_HTTP_GIT_PORT'] || 20010

SRV_HTTP_DOMAIN ||= config['SRV_HTTP_DOMAIN'] || ENV['SRV_HTTP_DOMAIN'] || 'api.compass-ci.openeuler.org'

SRV_HTTP_PROTOCOL ||=
  File.exist?('/etc/ssl/certs/web-backend.key') && File.exist?('/etc/ssl/certs/web-backend.crt') ? 'https' : 'http'

ASSISTANT_HOST ||= config['ASSISTANT_HOST'] || ENV['ASSISTANT_HOST'] || '172.17.0.1'
ASSISTANT_PORT ||= config['ASSISTANT_PORT'] || ENV['ASSISTANT_PORT'] || 8101

ASSIST_RESULT_HOST ||= config['ASSIST_RESULT_HOST'] || ENV['ASSIST_RESULT_HOST'] || '172.17.0.1'
ASSIST_RESULT_PORT ||= config['ASSIST_RESULT_PORT'] || ENV['ASSIST_RESULT_PORT'] || 8102

SCHED_HOST ||= config['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT ||= config['SCHED_PORT'] || 3000

LAB ||= config['LAB'] || ENV['LAB'] || 'z9'

OAUTH_CLIENT_ID ||= config['OAUTH_CLIENT_ID'] || ENV['OAUTH_CLIENT_ID'] || 'your_client_id_here'
OAUTH_CLIENT_SECRET ||= config['OAUTH_CLIENT_SECRET'] || ENV['OAUTH_CLIENT_SECRET'] || 'your_client_secret_here'
OAUTH_REDIRECT_URL ||= config['OAUTH_REDIRECT_URL'] || ENV['OAUTH_REDIRECT_URL'] || 'https://compass-ci.openeuler.org/oauth_authorize'
OAUTH_TOKEN_URL ||= config['OAUTH_TOKEN_URL'] || ENV['OAUTH_TOKEN_URL'] || "https://omapi.test.osinfra.cn/oneid/oidc/token"
OAUTH_USER_URL ||= config['OAUTH_USER_URL'] || ENV['OAUTH_USER_URL'] || "https://omapi.test.osinfra.cn/oneid/oidc/user"
JWT_SECRET ||= config['JWT_SECRET'] || ENV['JWT_SECRET'] || nil

PUBLISH_NO ||= 0
PUBLISH_WAITING ||= 1
PUBLISH_ABORTED ||= 2
PUBLISH_PUBLISHING ||= 3
PUBLISH_SUCCESS ||= 4
PUBLISH_FAILED ||= 5

ENABLE_AUTH_CODE_API = ENV['ENABLE_AUTH_CODE_API'] || config['ENABLE_AUTH_CODE_API'] || false
ENABLE_REGISTER_API = ENV['ENABLE_REGISTER_API'] || config['ENABLE_REGISTER_API'] || false
