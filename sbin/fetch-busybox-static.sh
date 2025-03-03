#!/bin/bash

# Define output directory
OUTPUT_DIR="${1:-$PWD}"
mkdir -p "$OUTPUT_DIR"

# Base URL for Debian packages
DEBIAN_MIRROR="https://ftp.debian.org/debian/pool/main/b/busybox"

# Function to log messages
log_message() {
    echo "[INFO] $1"
}

# Function to fetch the directory listing and parse the highest version
get_latest_version() {
    local arch="$1"
    # log_message "Fetching latest version for architecture: $arch..."

    # Fetch the directory listing and filter for busybox-static_<version>_<arch>.deb files
    wget -q -O - "$DEBIAN_MIRROR" | grep -oE 'busybox-static_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+(_[a-zA-Z0-9]+)?\.deb' | \
        grep "_${arch}\.deb" | sort -V | tail -n 1
}

# Function to download and extract static BusyBox binary
fetch_and_package_busybox() {
    local arch="$1"
    local package_name=$(get_latest_version "$arch")
    if [ -z "$package_name" ]; then
        log_message "No package found for architecture: $arch. Skipping."
        return
    fi

    local temp_dir=$(mktemp -d)

    log_message "Processing architecture: $arch (Package: $package_name)"

    # Step 1: Download the Debian package
    log_message "Downloading package for $arch..."
    wget -q "${DEBIAN_MIRROR}/${package_name}" -O "${temp_dir}/${package_name}"
    if [ $? -ne 0 ]; then
        log_message "Failed to download package for $arch. Skipping."
        rm -rf "$temp_dir"
        return
    fi

    # Step 2: Extract the .deb file
    log_message "Extracting package for $arch..."
    dpkg-deb -x "${temp_dir}/${package_name}" "$temp_dir"
    if [ $? -ne 0 ]; then
        log_message "Failed to extract package for $arch. Skipping."
        rm -rf "$temp_dir"
        return
    fi

    # Step 3: Locate the static BusyBox binary
    local busybox_binary="${temp_dir}/usr/bin/busybox"
    if [ ! -f "$busybox_binary" ]; then
        log_message "Static BusyBox binary not found for $arch. Skipping."
        rm -rf "$temp_dir"
        return
    fi

    # Step 4: Create a minimal root filesystem with the binary
    log_message "Creating minimal rootfs for $arch..."
    mkdir -p "${temp_dir}/rootfs/opt/busybox"
    mv "$busybox_binary" "${temp_dir}/rootfs/opt/busybox/busybox"
    cd "${temp_dir}/rootfs"
    # $busybox_binary --install -s bin > /dev/null 2>&1

    # Step 5: Package the rootfs into a cpio.gz archive
    log_message "Packaging into cpio.gz for $arch..."
    find . | cpio -o -H newc | gzip > "${OUTPUT_DIR}/busybox-static-${arch}.cgz"
    if [ $? -ne 0 ]; then
        log_message "Failed to create cpio.gz for $arch. Skipping."
        rm -rf "$temp_dir"
        return
    fi

    # Step 6: Create a symlink for x86_64, aarch64
    if [ "$arch" == "amd64" ]; then
        log_message "Creating symlink for aarch64 -> arm64..."
        ln -sf "busybox-static-amd64.cgz" "${OUTPUT_DIR}/busybox-static-x86_64.cgz"
    fi
    if [ "$arch" == "arm64" ]; then
        log_message "Creating symlink for aarch64 -> arm64..."
        ln -sf "busybox-static-arm64.cgz" "${OUTPUT_DIR}/busybox-static-aarch64.cgz"
    fi

    # Cleanup
    log_message "Finished processing $arch."
    rm -rf "$temp_dir"
}

# Main script logic
log_message "Starting BusyBox static binary fetch and packaging..."

# List of architectures to fetch
ARCHS=("amd64" "arm64" "i386" "ppc64el" "s390x" "armhf" "mips64el" "mipsel" "riscv64")

for arch in "${ARCHS[@]}"; do
    fetch_and_package_busybox "$arch"
done

log_message "All tasks completed. Output files are in '$OUTPUT_DIR'."
