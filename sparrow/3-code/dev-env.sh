#!/bin/bash

cat > /etc/profile.d/crystal.sh <<EOF
export LKP_SRC=/c/lkp-tests
export CCI_SRC=/c/crystal-ci
EOF

server_name=$(hostname | cut -f1 -d.)
server_ip=$(ip route get 1.2.3.4 | awk '{print $7; exit}')
cat > /c/lkp-tests/labs/$server_name.yaml <<EOF
SCHED_IP: $server_ip
SCHED_PORT: 3000
LKP_SERVER: $server_ip
LKP_CGI_PORT: 3000
EOF
