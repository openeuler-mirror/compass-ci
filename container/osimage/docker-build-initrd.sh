#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

source ${CCI_SRC}/container/osimage/lib
source ${CCI_SRC}/container/defconfig.sh
source ${CCI_SRC}/lib/log.sh

check_params "$@"

echo $OS_NAME
[ $OS_NAME == "openeuler" ] && load_oe_docker_image || pull_docker_image
run_docker
#cp_image_to_host
docker_rm initramfs_${OS_NAME}_${OS_VERSION}_$(date +"%Y%m%d") &> /dev/null
echo "build finished"
