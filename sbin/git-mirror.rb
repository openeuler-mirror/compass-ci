#!/usr/bin/env ruby
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

require "#{ENV['CCI_SRC']}/lib/git_mirror"

git_mirror = MirrorMain.new

git_mirror.create_workers
git_mirror.main_loop
