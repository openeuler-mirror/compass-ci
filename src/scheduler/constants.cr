# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "../taskqueue/constants"

JOB_REDIS_HOST       = "172.17.0.1"
JOB_REDIS_PORT       = 6379
JOB_REDIS_PORT_DEBUG = 6380

JOB_ES_HOST       = "172.17.0.1"
JOB_ES_PORT       = 9200
JOB_ES_PORT_DEBUG = 9201
JOB_INDEX_TYPE    = "jobs/_doc"

LAB = (ENV.has_key?("lab") ? ENV["lab"] : "nolab")

SCHED_HOST = (ENV.has_key?("SCHED_HOST") ? ENV["SCHED_HOST"] : "172.17.0.1")
SCHED_PORT = (ENV.has_key?("SCHED_PORT") ? ENV["SCHED_PORT"] : 3000).to_i32

INITRD_HTTP_HOST = (ENV.has_key?("INITRD_HTTP_HOST") ? ENV["INITRD_HTTP_HOST"] : "172.17.0.1")
INITRD_HTTP_PORT = (ENV.has_key?("INITRD_HTTP_PORT") ? ENV["INITRD_HTTP_PORT"] : 8800).to_i32

OS_HTTP_HOST = (ENV.has_key?("OS_HTTP_HOST") ? ENV["OS_HTTP_HOST"] : "172.17.0.1")
OS_HTTP_PORT = (ENV.has_key?("OS_HTTP_PORT") ? ENV["OS_HTTP_PORT"] : 8000).to_i32

SRV_HTTP_HOST = (ENV.has_key?("SRV_HTTP_HOST") ? ENV["SRV_HTTP_HOST"] : "172.17.0.1")
SRV_HTTP_PORT = (ENV.has_key?("SRV_HTTP_PORT") ? ENV["SRV_HTTP_PORT"] : "11300")

CCI_REPOS = (ENV.has_key?("CCI_REPOS") ? ENV["CCI_REPOS"] : "/c")
LAB_REPO  = "lab-z9"

SRV_OS     = "/srv/os"
SRV_INITRD = "/srv/initrd"

INITRD_HTTP_PREFIX = "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}"
OS_HTTP_PREFIX = "http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}"
SCHED_HTTP_PREFIX = "http://#{SCHED_HOST}:#{SCHED_PORT}"

DEMO_JOB = %({"suite":"pixz","testcase":"pixz","category":"benchmark","nr_threads":1,"pixz":null,"job_origin":"jobs/pixz.yaml","testbox":"wfg-e595","arch":"x86_64","tbox_group":"wfg-e595","id":"100","kmsg":null,"boot-time":null,"uptime":null,"iostat":null,"heartbeat":null,"vmstat":null,"numa-numastat":null,"numa-vmstat":null,"numa-meminfo":null,"proc-vmstat":null,"proc-stat":null,"meminfo":null,"slabinfo":null,"interrupts":null,"kconfig":"x86_64-rhel-7.6","compiler":"gcc-7"})
