# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.
# frozen_string_literal: true

LKP_SRC ||= ENV['LKP_SRC'] || '/c/lkp-tests'
MONITOR_HOST ||= ENV['MONITOR_HOST'] || '172.17.0.1'
MONITOR_PORT ||= ENV['MONITOR_PORT'] || '11310'
GIT_MIRROR_HOST ||= ENV['GIT_MIRROR_HOST'] || '172.17.0.1'
DELIMITER_EMAIL ||= ENV['DELIMITER_EMAIL'] || 'delimiter@localhost'
BISECT_RUN_SCRIPT = "#{ENV['CCI_SRC']}/src/delimiter/find-commit/bisect_run_script.rb"
# The files which are in this dir can be uploaded by lkp-tests
TMP_RESULT_ROOT ||= ENV['TMP_RESULT_ROOT'] || '/tmp/lkp/result'
TMEP_GIT_BASE = '/c/public_git'
PROCESS_JOB_YAML = "/tmp/process.yaml"
DELIMITER_TASK_QUEUE = 'delimiter'
