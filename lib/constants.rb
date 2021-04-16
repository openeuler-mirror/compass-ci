# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../container/defconfig.rb'

config = cci_defaults
ES_HOST ||= config['ES_HOST'] || '172.17.0.1'
ES_PORT ||= config['ES_PORT'] || 9200

SEND_MAIL_HOST ||= config['SEND_MAIL_HOST'] || '172.17.0.1'
SEND_MAIL_PORT ||= config['SEND_MAIL_PORT'] || 10001

SRV_HTTP_RESULT_HOST ||= config['SRV_HTTP_RESULT_HOST'] || ENV['SRV_HTTP_RESULT_HOST'] || '172.17.0.1'
SRV_HTTP_OS_HOST ||= config['SRV_HTTP_OS_HOST'] || ENV['SRV_HTTP_OS_HOST'] || '172.17.0.1'
SRV_HTTP_GIT_HOST ||= config['SRV_HTTP_GIT_HOST'] || ENV['SRV_HTTP_GIT_HOST'] || '172.17.0.1'
SRV_HTTP_RESULT_PORT ||= config['SRV_HTTP_RESULT_PORT'] || ENV['SRV_HTTP_RESULT_PORT'] || 20007
SRV_HTTP_OS_PORT ||= config['SRV_HTTP_OS_PORT'] || ENV['SRV_HTTP_OS_PORT'] || 20009
SRV_HTTP_GIT_PORT ||= config['SRV_HTTP_GIT_PORT'] || ENV['SRV_HTTP_GIT_PORT'] || 20010

SRV_HTTP_DOMAIN ||= config['SRV_HTTP_DOMAIN'] || ENV['SRV_HTTP_DOMAIN'] || 'api.compass-ci.openeuler.org'

ASSISTANT_HOST ||= config['ASSISTANT_HOST'] || ENV['ASSISTANT_HOST'] || '172.17.0.1'
ASSISTANT_PORT ||= config['ASSISTANT_PORT'] || ENV['ASSISTANT_PORT'] || 8101

ASSIST_RESULT_HOST ||= config['ASSIST_RESULT_HOST'] || ENV['ASSIST_RESULT_HOST'] || '172.17.0.1'
ASSIST_RESULT_PORT ||= config['ASSIST_RESULT_PORT'] || ENV['ASSIST_RESULT_PORT'] || 8102

SCHED_HOST ||= config['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT ||= config['SCHED_PORT'] || 3000
