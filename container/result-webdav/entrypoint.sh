#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+

umask 002

sed -i 's/user  nginx/user  lkp/g' /etc/nginx/nginx.conf

sed 's|worker_processes  auto|worker_processes  30|' /etc/nginx/nginx.conf

nginx -g "daemon off;"
