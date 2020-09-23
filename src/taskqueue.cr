# SPDX-License-Identifier: MulanPSL-2.0+ or GPL-2.0
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

require "./taskqueue/taskqueue"

taskqueue = TaskQueue.new
taskqueue.run
