#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require_relative './docker/docker'

start(ENV['hostname'], ENV['queues'], ENV['uuid'], ENV['index'], ENV['maxdc'], ENV['is_remote'])
