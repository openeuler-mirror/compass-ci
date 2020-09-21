#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

DIR=$(dirname $(realpath $0))
ruby $DIR/../src/lkp.rb queue $1
