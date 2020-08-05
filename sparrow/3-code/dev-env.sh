#!/usr/bin/env bash

server_name=$(hostname | cut -f1 -d.)
server_ip=$(ip route get 1.2.3.4 | awk '{print $7; exit}')

mkdir -p /etc/crystal-ci/defaults
cat >    /etc/crystal-ci/defaults/$server_name.yaml <<EOF
SCHED_HOST: $server_ip
SCHED_PORT: 3000
LKP_SERVER: $server_ip
LKP_CGI_PORT: 3000
EOF

cat > /etc/profile.d/crystal.sh <<EOF
export LKP_SRC=/c/lkp-tests
export CCI_SRC=/c/crystal-ci

export PATH="$PATH:$CCI_SRC/sbin:$LKP_SRC/sbin:$LKP_SRC/bin"
EOF
