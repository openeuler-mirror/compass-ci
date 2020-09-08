# SPDX-License-Identifier: MulanPSL-2.0+

JOB_REDIS_HOST = "172.17.0.1"
JOB_REDIS_PORT = 6379
JOB_REDIS_PORT_DEBUG = 6380

JOB_ES_HOST = "172.17.0.1"
JOB_ES_PORT = 9200
JOB_ES_PORT_DEBUG = 9201
JOB_INDEX_TYPE = "jobs/_doc"

LAB = (ENV.has_key?("LAB") ? ENV["LAB"] : "crystal-ci")

SCHED_HOST = (ENV.has_key?("SCHED_HOST") ? ENV["SCHED_HOST"] : "172.17.0.1")
SCHED_PORT = (ENV.has_key?("SCHED_PORT") ? ENV["SCHED_PORT"] : 3000).to_i32

INITRD_HTTP_HOST = (ENV.has_key?("INITRD_HTTP_HOST") ? ENV["INITRD_HTTP_HOST"] : "172.168.131.113")
INITRD_HTTP_PORT = (ENV.has_key?("INITRD_HTTP_PORT") ? ENV["INITRD_HTTP_PORT"] : 8800).to_i32

OS_HTTP_HOST = (ENV.has_key?("OS_HTTP_HOST") ? ENV["OS_HTTP_HOST"] : "172.168.131.113")
OS_HTTP_PORT = (ENV.has_key?("OS_HTTP_PORT") ? ENV["OS_HTTP_PORT"] : 8000).to_i32

DEMO_JOB = %({"suite":"pixz","testcase":"pixz","category":"benchmark","nr_threads":1,"pixz":null,"job_origin":"jobs/pixz.yaml","testbox":"wfg-e595","arch":"x86_64","tbox_group":"wfg-e595","id":"100","kmsg":null,"boot-time":null,"uptime":null,"iostat":null,"heartbeat":null,"vmstat":null,"numa-numastat":null,"numa-vmstat":null,"numa-meminfo":null,"proc-vmstat":null,"proc-stat":null,"meminfo":null,"slabinfo":null,"interrupts":null,"kconfig":"x86_64-rhel-7.6","compiler":"gcc-7"})
