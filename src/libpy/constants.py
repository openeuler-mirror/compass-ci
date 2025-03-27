#! /usr/bin/env python
# coding=utf-8
# ******************************************************************************
# Copyright (c) Huawei Technologies Co., Ltd. 2020-2020. All rights reserved.
# licensed under the Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#     http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v2 for more details.
# Author: He Shoucheng
# Create: 2022-07-12
# ******************************************************************************/

import os
import inspect


class SystemRoles:
    ADMIN = "admin"
    STANDARD = "standard"


class ProjectRoles:
    MAINTAINER = "maintainer"
    READER = "reader"

ALL_ROLES = [ProjectRoles.MAINTAINER, ProjectRoles.READER]

# 构建任务类型
class BuildType:
    FULL = "full"
    INCREMENTAL = "incremental"
    SINGLE = "single"
    MAKEHOTPATCH = "makehotpatch"
    SPEED_FULL = "speed_full"
    SPEED_INCREMENTAL = "speed_incremental"
    FULL_SPLIT_INCREMENTAL = "incremental_from_full"
    FULL_SPLIT_SINGLE = "single_batch_from_full"
    SPECIFIED = "specified"
    SINGLE_BATCH = "single_batch"
    INCLUDE_BUILD_DEP_TYPES = [FULL, INCREMENTAL, \
                                SPEED_FULL, SPEED_INCREMENTAL, \
                                FULL_SPLIT_INCREMENTAL, SPECIFIED, SINGLE_BATCH]


class DcgDictType:
    ORIGIN = "origin"
    VISUALIZATION = "broken_cycles"


class SpecDictType:
    NORMAL = "spec_file_path_dict"
    DOWNLOAD_FAILED = "download_failed_dict"
    BLANK_SPEC = "blank_spec_dict"
    NO_SPEC = "no_spec_dict"
    GET_SPEC_NAME_FAILED = "get_spec_name_failed_dict"
    UNSUPPORTED_ARCH = "unsupported_arch_dict"
    PARSE_SPEC_FAILED = "parse_spec_failed_dict"

# 请求submit超时时间
MAX_CALL_SUBMIT = 600
MAX_ZIP_COMPRESS_RATIO = 300
USE_SINGLE_THREAD_SPEED = True
DAG_CALCULATE_SPEED = False
DAG_THREAD_LOOP_WAIT_TIME = 10

# 支持架构列表
EXCLUSIVE_ARCH = ["x86_64", "aarch64", "loongarch64", "riscv64", "ppc64le", "sw_64"]

AUTH_HOST = os.getenv("AUTH_HOST", '172.17.0.1')
AUTH_PORT = os.getenv("AUTH_PORT", 10002)
# project相关api请求路径用/切割后list的最小长度
OS_PROJECT_PATH_ITEM_LIST_LEN = 3

ES_REFRESH_TIME = 60
REDIS_REFRESH_TIME = 10
# dag接收到一个请求，需要一定的时间去解析repo准备数据
DELAY_START_WATCH_BUILD = 120
DELAY_WATCH_REQUESTS = 5
ETCD_RETRY_TIME = 30

MAX_STABLE_STATS_LOOPS = 5
MIN_CYCLE_BUILD = 2
MAX_COMMON_BUILD = 2

DAG_HOST = os.getenv("DAG_HOST", "172.17.0.1")
DAG_PORT = os.getenv("DAG_PORT", 20036)

PUBLISHER_HOST = os.getenv("PUBLISHER_HOST", "172.17.0.1")
PUBLISHER_PORT = os.getenv("PUBLISHER_PORT", 20037)

ETCD_HOST = os.getenv("ETCD_HOST", "172.17.0.1")
ETCD_PORT = os.getenv("ETCD_PORT", 2379)

SCHED_HOST = os.getenv("SCHED_HOST", "172.17.0.1")
SCHED_PORT = os.getenv("SCHED_PORT", 3000)

ETCD_GET_LIMIT = 5000
ES_GET_LIMIT = 10000

REDIS_HOST = os.getenv("REDIS_HOST", "172.17.0.1")
REDIS_PORT = os.getenv("REDIS_PORT", 6379)

REMOTE_GIT_HOST = os.getenv("REMOTE_GIT_HOST", "172.17.0.1")
REMOTE_GIT_PORT = os.getenv("REMOTE_GIT_PORT", 8100)

GIT_SERVER = os.getenv("GIT_SERVER", "172.17.0.1")

# repo对外的主机(包括工程构建结果的repo和分层定制生成的repo)
REPO_HOST = os.getenv('REPO_HOST', '172.17.0.1')

MQ_HOST = os.getenv('MQ_HOST', '172.17.0.1')
MQ_PORT = os.getenv('MQ_PORT', 5672)

TIMER_HOST = os.getenv('TIMER_HOST', '172.17.0.1')
TIMER_PORT = os.getenv('TIMER_PORT', 20034)
