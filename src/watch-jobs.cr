# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./watch-jobs/watch_jobs"
require "./lib/json_logger"

log = JSONLogger.new

begin
  WatchJobs.new().handle_jobs()
rescue e
  log.error(e)
end
