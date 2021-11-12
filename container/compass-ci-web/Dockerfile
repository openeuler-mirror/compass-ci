# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM node:lts-alpine3.14 as Builder

MAINTAINER Lu Weitao <luweitaobe@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

COPY ./crystal-ci /compass-ci-web
WORKDIR /compass-ci-web

RUN npm i --legacy-peer-deps &&\
    npm install && \
    npm run build

FROM nginx:1.20.0-alpine

ADD root /

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

COPY --from=Builder /compass-ci-web/dist /usr/share/nginx/html/
RUN chmod -R 755 /usr/share/nginx/html

ENV RUN_USER nginx
ENV RUN_GROUP nginx

ENTRYPOINT ["/sbin/entrypoint.sh"]
