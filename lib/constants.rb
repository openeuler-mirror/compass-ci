# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative '../container/defconfig.rb'

config = cci_defaults
ES_HOST = config['ES_HOST'] || '172.17.0.1'
ES_PORT = config['ES_PORT'] || 9200

MAIL_HOST = config['MAIL_HOST'] || '172.17.0.1'
MAIL_PORT = config['MAIL_PORT'] || 11_311
