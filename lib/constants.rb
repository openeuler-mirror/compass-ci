# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../container/defconfig.rb'

config = cci_defaults
ES_HOST ||= config['ES_HOST'] || '172.17.0.1'
ES_PORT ||= config['ES_PORT'] || 9200

SEND_MAIL_HOST ||= config['SEND_MAIL_HOST'] || '172.17.0.1'
SEND_MAIL_PORT ||= config['SEND_MAIL_PORT'] || 49000

SRV_HTTP_HOST ||= config['SRV_HTTP_HOST'] || ENV['SRV_HTTP_HOST'] || '172.17.0.1'
SRV_HTTP_PORT ||= config['SRV_HTTP_PORT'] || ENV['SRV_HTTP_PORT'] || 11300

SRV_HTTP_DOMAIN ||= config['SRV_HTTP_DOMAIN'] || ENV['SRV_HTTP_DOMAIN'] || 'api.compass-ci.openeuler.org'

ASSIST_RESULT_HOST ||= config['ASSIST_RESULT_HOST'] || ENV['ASSIST_RESULT_HOST'] || '172.17.0.1'
ASSIST_RESULT_PORT ||= config['ASSIST_RESULT_PORT'] || ENV['ASSIST_RESULT_PORT'] || 8102

SCHED_HOST ||= config['SCHED_HOST'] || '172.17.0.1'
SCHED_PORT ||= config['SCHED_PORT'] || 3000
