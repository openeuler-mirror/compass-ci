# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

FROM alpine:3.9

ADD root /

RUN apk add --no-cache nginx php7 php7-fpm php7-session php7-json php7-exif php7-imagick php7-gd php7-fileinfo nodejs npm \
    && mkdir /run/nginx/ \
    && mkdir /h5ai

RUN sed -i '/\[global\]/a daemonize = no' /etc/php7/php-fpm.conf
RUN sed -i "s/user = nobody/user = nginx/g" /etc/php7/php-fpm.d/www.conf
RUN sed -i "s/group = nobody/group = nginx/g" /etc/php7/php-fpm.d/www.conf

WORKDIR /h5ai
COPY h5ai /h5ai

# build h5ai package
RUN npm install \
    && npm run build \
    && cp -r ./build/_h5ai /srv \
    && chown -R nginx:nginx /srv/_h5ai

ENTRYPOINT ["/sbin/entrypoint.sh"]
