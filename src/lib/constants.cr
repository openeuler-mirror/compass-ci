# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

BASE = "/queues"

ETCD_HOST = (ENV.has_key?("ETCD_HOST") ? ENV["ETCD_HOST"] : "172.17.0.1")
ETCD_PORT = (ENV.has_key?("ETCD_PORT") ? ENV["ETCD_PORT"] : 2379).to_i32
ETCD_VERSION = "v3beta"

TOTAL_JOBS_QUOTA = (ENV.has_key?("TOTAL_JOBS_QUOTA") ? ENV["TOTAL_JOBS_QUOTA"] : 150000).to_i32

COMMON_PARAMS = %w[tbox_group os os_arch os_version]

CI_ACCOUNTS = ["openeuler_cicd"]
ADMIN_ACCOUNTS = ["admin"]

DEV_BRANCHES = ["develop"]
TTM_BRANCHES = ["maintenance"]
PROJECT_JSON = "#{ENV["CCI_SRC"]}/src/lib/openeuler-projects.json"
# hw is the pyhsical machine
TBOX_TYPES = ["dc", "vm", "hw"]
