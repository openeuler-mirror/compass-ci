#!/bin/bash
# kernel-boot2os.sh - Orchestrate fetch and extract processes

if [ -w /srv ]; then
    BASE_DIR="/srv"
else
    BASE_DIR="$HOME/.cache/compass-ci"
fi
export BASE_DIR

SCRIPT_DIR=$(dirname $(realpath $0))

# OS list: Format - "OS_NAME OS_VERSION ARCH PACKAGE_URL"
SUSE_OS_LIST=(
    # openSUSE
    "opensuse   15.6       x86_64     https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/x86_64/"
    "opensuse   15.6       aarch64    https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/aarch64/"
)

OS_LIST=(

    # openEuler
    "openeuler  20.03      x86_64     https://repo.openeuler.org/openEuler-20.03-LTS-SP4/everything/x86_64/Packages/"
    "openeuler  20.03      aarch64    https://repo.openeuler.org/openEuler-20.03-LTS-SP4/everything/aarch64/Packages/"
    "openeuler  22.03      x86_64     https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/x86_64/Packages/"
    "openeuler  22.03      aarch64    https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/aarch64/Packages/"
    "openeuler  22.03      riscv64    https://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/riscv64/Packages/"

    "openeuler  24.03      x86_64     https://repo.openeuler.org/openEuler-24.03-LTS-SP1/everything/x86_64/Packages/"
    "openeuler  24.03      aarch64    https://repo.openeuler.org/openEuler-24.03-LTS-SP1/everything/aarch64/Packages/"
    "openeuler  24.03      riscv64    https://repo.openeuler.org/openEuler-24.03-LTS-SP1/everything/riscv64/Packages/"

    "openeuler  24.09      x86_64     https://repo.openeuler.org/openEuler-24.09/everything/x86_64/Packages/"
    "openeuler  24.09      aarch64    https://repo.openeuler.org/openEuler-24.09/everything/aarch64/Packages/"
    "openeuler  24.09      riscv64    https://repo.openeuler.org/openEuler-24.09/everything/riscv64/Packages/"

    # Fedora
    "fedora     41         aarch64    http://mirrors.163.com/fedora/updates/41/Everything/aarch64/Packages/k/"
    "fedora     41         x86_64     http://mirrors.163.com/fedora/updates/41/Everything/x86_64/Packages/k/"

    # Ubuntu
    "ubuntu     24.04      amd64      http://mirrors.163.com/ubuntu/pool/main/l/linux-signed/"
    "ubuntu     24.04      amd64      http://mirrors.163.com/ubuntu/pool/main/l/linux/"
    "ubuntu     24.04      arm64      http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux-signed/"
    "ubuntu     24.04      arm64      http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/"
    "ubuntu     24.04      riscv64    http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux-riscv/"

    # Debian
    "debian     12         amd64      http://mirrors.163.com/debian/pool/main/l/linux-signed-amd64/"
    "debian     12         arm64      http://mirrors.163.com/debian/pool/main/l/linux-signed-arm64/"
    "debian     12         riscv64    http://mirrors.163.com/debian/pool/main/l/linux/"
    "debian     12         loongson   http://mirrors.163.com/debian/pool/main/l/linux/"

    # Below are not well supported

    # CentOS Stream
    # problem: no kernel image here
    # "centos     9          x86_64     https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/"
    # "centos     9          aarch64    https://mirror.stream.centos.org/9-stream/AppStream/aarch64/os/Packages/"

    # Rocky Linux
    # "rocky      9.5        aarch64    http://mirrors.163.com/rocky/9.5/BaseOS/aarch64/os/Packages/k/"
    # "rocky      9.5        x86_64     http://mirrors.163.com/rocky/9.5/BaseOS/x86_64/os/Packages/k/"

    # Arch Linux
    "archlinux  latest     x86_64     https://mirror.rackspace.com/archlinux/core/os/x86_64/"
    "archlinux  latest     aarch64    https://mirror.rackspace.com/archlinux/core/os/aarch64/"

    # Manjaro
    "manjaro    24.0       x86_64     https://mirror.rackspace.com/manjaro/stable/core/x86_64/"
    "manjaro    24.0       aarch64    https://mirror.rackspace.com/manjaro/stable/core/aarch64/"

    # Alpine Linux
    "alpine     3.21       amd64      https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/"
    "alpine     3.21       arm64      https://dl-cdn.alpinelinux.org/alpine/v3.21/main/aarch64/"
    "alpine     3.21       armv7      https://dl-cdn.alpinelinux.org/alpine/v3.21/main/armv7/"

    # Gentoo
    "gentoo     latest     amd64      https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/"
    "gentoo     latest     arm64      https://distfiles.gentoo.org/releases/arm64/autobuilds/current-stage3-arm64/"
)

# Map architecture names (Debian -> Standard)
map_architecture() {
    case "$1" in
        arm64) echo "aarch64" ;;
        amd64) echo "x86_64" ;;
        *) echo "$1" ;;
    esac
}

# Fetch phase
for entry in "${OS_LIST[@]}" "${SUSE_OS_LIST[@]}"; do
    read -r os os_version arch url <<< "$entry"
    $SCRIPT_DIR/kernel-fetch.sh "$os" "$os_version" "$arch" "$url"
done

# Process SUSE with different flavors
for flavor in default 64kb kvmsmall rt; do
    for entry in "${SUSE_OS_LIST[@]}"; do
        read -r os os_version arch url <<< "$entry"
        $SCRIPT_DIR/kernel-fetch.sh "$os" "$os_version" "$arch" "$url" "$flavor"
    done
done

# Extract phase
for entry in "${OS_LIST[@]}" "${SUSE_OS_LIST[@]}"; do
    read -r os os_version arch url <<< "$entry"
    mapped_arch=$(map_architecture "$arch")
    download_dir="$BASE_DIR/downloads/$mapped_arch/$os@$os_version"
    for version_dir in "$download_dir"/*; do
        [ -d "$version_dir" ] && $SCRIPT_DIR/kernel-extract.sh "$version_dir"
    done
done

echo "All processes completed successfully"

# vim:set ts=4 sw=4 et:
