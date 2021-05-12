# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM node:alpine as Builder

MAINTAINER Lu Weitao <luweitaobe@163.com>

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk update

RUN apk add git

RUN git clone https://gitee.com/luweitao_y/h5ai.git /h5ai

WORKDIR /h5ai

RUN npm install && \
    npm run build

FROM nginx:alpine

ADD root /

RUN sed -ri.origin 's|^https?://dl-cdn.alpinelinux.org|http://mirrors.huaweicloud.com|g' /etc/apk/repositories

RUN apk add --no-cache php7 php7-fpm php7-session php7-json php7-exif php7-imagick php7-gd php7-fileinfo

RUN sed -i '/\[global\]/a daemonize = no' /etc/php7/php-fpm.conf
RUN sed -i "s/user = nobody/user = nginx/g" /etc/php7/php-fpm.d/www.conf
RUN sed -i "s/group = nobody/group = nginx/g" /etc/php7/php-fpm.d/www.conf


COPY --from=Builder /h5ai/build/_h5ai /srv/_h5ai

RUN chown -R nginx:nginx /srv/_h5ai

ENTRYPOINT ["/sbin/entrypoint.sh"]
