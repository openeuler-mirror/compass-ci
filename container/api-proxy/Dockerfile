# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM nginx:1.20.0-alpine

MAINTAINER Lu Weitao <luweitaobe@163.com>

COPY nginx.conf /etc/nginx/

ENV RUN_USER nginx
ENV RUN_GROUP nginx
EXPOSE 9092
ENTRYPOINT ["nginx", "-g", "daemon off;"]
