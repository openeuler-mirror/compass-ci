#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

rev=$(etcdctl endpoint status --write-out="json"|egrep -o '"revision":[0-9]*'|egrep -o '[0-9].*')
etcdctl compact $rev && etcdctl defrag
