# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# frozen_string_literal: true

require_relative '../container/lab.rb'

config = cci_defaults
ES_HOST = config['ES_HOST'] || '172.17.0.1'
ES_PORT = config['ES_PORT'] || 9200
