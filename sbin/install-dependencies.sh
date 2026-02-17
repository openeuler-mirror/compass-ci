#!/usr/bin/env bash

# Converted to use epkg with Alpine environment
# Original script detected distribution and used native package manager
# Now uses epkg environment at .eenv for consistent dependency installation

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/sbin}"

cd "$PROJECT_ROOT" || exit

# Function to check if epkg environment exists
ensure_epkg_env() {
    local env_dir=".eenv"
    if [ ! -d "$env_dir" ]; then
        echo "Creating epkg Alpine environment in $env_dir"
        epkg env create --root "$env_dir" -c alpine
        if [ $? -ne 0 ]; then
            echo "Failed to create epkg environment"
            exit 1
        fi
    else
        echo "Using existing epkg environment in $env_dir"
    fi
}

# Install dependencies using epkg
install_dependencies() {
    ensure_epkg_env

    echo "Installing crystal, shards, rpm2cpio via epkg"
    # epkg will auto-find and use the environment at .eenv
    epkg install crystal shards \
        rpm2cpio bash \
        openssl-dev openssl-libs-static \
        yaml-dev yaml-static \
        zlib-dev zlib-static \
        gc-static pcre2-static \
        ruby-dev

    if [ $? -eq 0 ]; then
        echo "Successfully installed dependencies"
        test -h .eenv/bin/sh ||
        ln -s bash .eenv/bin/sh
    else
        echo "Failed to install dependencies"
        exit 1
    fi
}

# Main script logic
install_dependencies
