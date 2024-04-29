# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM nginx:1.25-alpine3.18

MAINTAINER Lu Weitao <luweitaobe@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories
RUN apk update --no-cache && \
    apk upgrade

COPY root /

#RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

#RUN chown -R nginx:nginx /srv/_h5ai

# Disable access logs without affecting the printing of error logs
RUN sed -i '/server {/a \ \ \ \ access_log off;' /etc/nginx/conf.d/default.conf

RUN chown -R nginx:nginx /etc/nginx

RUN chown nginx:nginx /var/cache/nginx /var/run
ENTRYPOINT ["/sbin/entrypoint.sh"]
