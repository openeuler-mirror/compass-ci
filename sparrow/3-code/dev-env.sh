#!/bin/bash

cat > /etc/profile.d/crystal.sh <<EOF
export LKP_SRC=/c/lkp-tests
export CCI_SRC=/c/crystal-ci
EOF
