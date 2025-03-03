#!/bin/bash

# Define output directory
if [ -n "$1" ]; then
	OUTPUT_DIR="$1"
else
	if [ -w /srv ]; then
		BASE_DIR="/srv"
	else
		BASE_DIR="$HOME/.cache/compass-ci"
	fi

	OUTPUT_DIR=$BASE_DIR/file-store/busybox
fi
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

    # Step 4: Create output directories
    local arch_output_dir="${OUTPUT_DIR}/${arch}"
    mkdir -p "$arch_output_dir"

    # Step 5: Copy the busybox binary to the output directory
    log_message "Copying busybox binary for $arch..."
    cp -a "$busybox_binary" "${arch_output_dir}/busybox"

    # Step 6: Create a minimal root filesystem with the binary
    log_message "Creating minimal rootfs for $arch..."
    mkdir -p "${temp_dir}/rootfs/opt/busybox"
    mv "$busybox_binary" "${temp_dir}/rootfs/opt/busybox/busybox"
    cd "${temp_dir}/rootfs" || exit

    # Step 7: Package the rootfs into a cpio.gz archive
    log_message "Packaging into cpio.gz for $arch..."
    find . | cpio -o -H newc | gzip > "${arch_output_dir}/busybox-static.cgz"
    if [ $? -ne 0 ]; then
        log_message "Failed to create cpio.gz for $arch. Skipping."
        rm -rf "$temp_dir"
        return
    fi

    # Step 8: Create symlinks for x86_64, aarch64
    if [ "$arch" == "amd64" ]; then
        log_message "Creating symlink for x86_64 -> amd64..."
        ln -sf "amd64" "${OUTPUT_DIR}/x86_64"
    fi
    if [ "$arch" == "arm64" ]; then
        log_message "Creating symlink for aarch64 -> arm64..."
        ln -sf "arm64" "${OUTPUT_DIR}/aarch64"
    fi

    # Cleanup
    log_message "Finished processing $arch."
    rm -rf "$temp_dir"
}

# Function to install busybox applets and copy symlinks to other archs
install_busybox_applets() {
    local current_arch=$(arch)
    local current_arch_dir="${OUTPUT_DIR}/${current_arch}"

    if [ ! -d "$current_arch_dir" ]; then
        log_message "Current architecture $current_arch not found in output directory. Skipping applet installation."
        return
    fi

    log_message "Installing busybox applets for $current_arch..."
    cd "$current_arch_dir" || exit
    ./busybox --install -s .
    convert_symlinks .

    log_message "Copying applet symlinks to other architectures..."
    for arch in "${ARCHS[@]}"; do
	arch_dir="${OUTPUT_DIR}/$arch"
        if [ "$arch_dir" != "$current_arch_dir" ] && [ -d "$arch_dir" ]; then
            cp -a --update=none "${current_arch_dir}/"* "$arch_dir/"
        fi
    done
}

# Function to convert absolute symlinks to relative ones
convert_symlinks() {
  local symlink_target
  local symlink_dir
  local relative_path
  local target_dir=$1

  # Find all symlinks in the target directory
  find "$target_dir" -type l | while read -r symlink; do
    # Get the target of the symlink
    symlink_target=$(readlink "$symlink")

    # Check if the symlink target is an absolute path
    if [[ "$symlink_target" == /* ]]; then
      # Get the directory containing the symlink
      symlink_dir=$(dirname "$symlink")

      # Convert the absolute path to a relative path
      relative_path=$(realpath --relative-to="$symlink_dir" "$symlink_target")

      # Remove the old symlink
      rm "$symlink"

      # Recreate the symlink with the relative path
      ln -s "$relative_path" "$symlink"

      echo "Converted: $symlink -> $relative_path"
    fi
  done
}

# Main script logic
log_message "Starting BusyBox static binary fetch and packaging..."

# List of architectures to fetch
ARCHS=("amd64" "arm64" "i386" "ppc64el" "s390x" "armhf" "mips64el" "mipsel" "riscv64")

for arch in "${ARCHS[@]}"; do
    fetch_and_package_busybox "$arch"
done

# Install busybox applets and copy symlinks to other archs
install_busybox_applets

log_message "All tasks completed. Output files are in '$OUTPUT_DIR'."
