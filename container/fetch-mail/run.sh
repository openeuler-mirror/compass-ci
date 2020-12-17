#!/bin/sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

mail_conf ()
{
        sed -i "s|FETCH_MAIL_ADDRESS|${FETCH_MAIL_ADDRESS}|g" '.fetchmailrc'
        sed -i "s|FETCH_MAIL_AUTH_CODE|${FETCH_MAIL_AUTH_CODE}|g" '.fetchmailrc'
        sed -i "s|FETCH_MAIL_DIR|${FETCH_MAIL_DIR}|g" '.procmailrc'
        sed -i "s|FETCH_MAIL_BOX|${FETCH_MAIL_BOX}|g" '.procmailrc'
}

mail_conf
fetchmail -d 100
