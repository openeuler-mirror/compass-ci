# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

LIFECYCLE_PORT = (ENV.has_key?("LIFECYCLE_PORT") ? ENV["LIFECYCLE_PORT"] : 11312).to_i32
JOB_CLOSE_STATE = ["abnormal", "close", "failed", "finished", "timeout", "crash"]
JOB_KEYWORDS = ["testbox", "job_stage", "deadline", "time"]
TESTBOX_KEYWORDS = ["state", "job_id", "deadline", "time"]
MACHINE_CLOSE_STATE = ["real_rebooting", "rebooting_queue"]
