#!/usr/bin/env sh
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# Below script mainly borrow from https://github.com/panubo/docker-sshd.git
# It use MIT LICENSE

set -e
DAEMON=sshd
echo "> Starting SSHD"

set_hostkeys() {
    printf '%s\n' \
        'set /files/etc/ssh/sshd_config/HostKey[1] /etc/ssh/keys/ssh_host_rsa_key' \
        'set /files/etc/ssh/sshd_config/HostKey[2] /etc/ssh/keys/ssh_host_dsa_key' \
        'set /files/etc/ssh/sshd_config/HostKey[3] /etc/ssh/keys/ssh_host_ecdsa_key' \
        'set /files/etc/ssh/sshd_config/HostKey[4] /etc/ssh/keys/ssh_host_ed25519_key' \
    | augtool -s 1> /dev/null
}

print_fingerprints() {
    local BASE_DIR=${1-'/etc/ssh'}
    for item in dsa rsa ecdsa ed25519; do
        echo ">>> Fingerprints for ${item} host key"
        ssh-keygen -E md5 -lf ${BASE_DIR}/ssh_host_${item}_key
        ssh-keygen -E sha256 -lf ${BASE_DIR}/ssh_host_${item}_key
        ssh-keygen -E sha512 -lf ${BASE_DIR}/ssh_host_${item}_key
    done
}

# Generate Host keys, if required
if ls /etc/ssh/keys/ssh_host_* 1> /dev/null 2>&1; then
    echo ">> Found host keys in keys directory"
    set_hostkeys
    print_fingerprints /etc/ssh/keys
elif ls /etc/ssh/ssh_host_* 1> /dev/null 2>&1; then
    echo ">> Found Host keys in default location"
    # Don't do anything
    print_fingerprints
else
    echo ">> Generating new host keys"
    mkdir -p /etc/ssh/keys
    ssh-keygen -A
    mv /etc/ssh/ssh_host_* /etc/ssh/keys/
    set_hostkeys
    print_fingerprints /etc/ssh/keys
fi

configure_ssh_options() {
    # Enable AllowTcpForwarding
    if [[ "${TCP_FORWARDING}" == "true" ]]; then
        echo 'set /files/etc/ssh/sshd_config/AllowTcpForwarding yes' | augtool -s 1> /dev/null
    fi
    # Enable GatewayPorts
    if [[ "${GATEWAY_PORTS}" == "true" ]]; then
        echo 'set /files/etc/ssh/sshd_config/GatewayPorts yes' | augtool -s 1> /dev/null
    fi
    # Disable SFTP
    if [[ "${DISABLE_SFTP}" == "true" ]]; then
        printf '%s\n' \
            'rm /files/etc/ssh/sshd_config/Subsystem/sftp' \
            'rm /files/etc/ssh/sshd_config/Subsystem' \
        | augtool -s 1> /dev/null
    fi
}

configure_ssh_options

# Enable PubkeyAuthentication
echo 'set /files/etc/ssh/sshd_config/PubkeyAuthentication yes' | augtool -s 1> /dev/null

stop() {
    echo "Received SIGINT or SIGTERM. Shutting down $DAEMON"
    # Get PID
    local pid=$(cat /var/run/$DAEMON/$DAEMON.pid)
    # Set TERM
    kill -SIGTERM "${pid}"
    # Wait for exit
    wait "${pid}"
    # All done.
    echo "Done."
}

echo "Running $@"
if [ "$(basename $1)" == "$DAEMON" ]; then
    trap stop SIGINT SIGTERM
    $@ &
    pid="$!"
    mkdir -p /var/run/$DAEMON && echo "${pid}" > /var/run/$DAEMON/$DAEMON.pid
    wait "${pid}"
    exit $?
else
    exec "$@"
fi
