#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+

umask 002
/usr/local/openresty/bin/openresty -g 'daemon off;'
