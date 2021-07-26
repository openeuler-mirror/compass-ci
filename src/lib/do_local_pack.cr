# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

def do_local_pack()
  %x(#{ENV["LKP_SRC"]}/sbin/do-local-pack)
end
