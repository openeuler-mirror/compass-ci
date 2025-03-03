#!/bin/bash
set -o pipefail

# OS list: Format - "OS_NAME OS_VERSION ARCH PACKAGE_URL"
OS_LIST=(
    # openEuler
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
    "fedora     41         aarch64    https://download.fedoraproject.org/pub/fedora/linux/releases/41/Everything/aarch64/os/Packages/"
    "fedora     41         x86_64     https://download.fedoraproject.org/pub/fedora/linux/releases/41/Everything/x86_64/os/Packages/"

    # CentOS Stream
    "centos     9          x86_64     https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/"
    "centos     9          aarch64    https://mirror.stream.centos.org/9-stream/AppStream/aarch64/os/Packages/"

    # openSUSE
    "opensuse   15.6       x86_64     https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/x86_64/"
    "opensuse   15.6       aarch64    https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/aarch64/"

)

OTHER_OS_LIST=(
    # Red Hat Enterprise Linux (RHEL)
    "rhel       9          x86_64     https://cdn.redhat.com/content/dist/rhel9/9.2/x86_64/appstream/os/Packages/"
    "rhel       9          aarch64    https://cdn.redhat.com/content/dist/rhel9/9.2/aarch64/appstream/os/Packages/"

    # Ubuntu
    "ubuntu     24.04      amd64      http://archive.ubuntu.com/ubuntu/dists/noble/main/binary-amd64/Packages"
    "ubuntu     24.04      arm64      http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-arm64/Packages"
    "ubuntu     24.04      ppc64el    http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-ppc64el/Packages"

    # Debian
    "debian     12         amd64      https://deb.debian.org/debian/dists/bookworm/main/binary-amd64/Packages"
    "debian     12         arm64      https://deb.debian.org/debian/dists/bookworm/main/binary-arm64/Packages"
    "debian     12         armhf      https://deb.debian.org/debian/dists/bookworm/main/binary-armhf/Packages"

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

if [ -w /srv ]; then
	BASE_DIR="/srv"
else
	BASE_DIR="$HOME/.cache/compass-ci"
fi
mkdir -p "$BASE_DIR"

# Function to process RPM-based OS
process_rpm_os() {
    local os="$1" os_version="$2" arch="$3" package_url="$4"
    echo "Processing RPM OS: $os $os_version $arch"

    # Fetch package listing
    local packages=$(curl -s "$package_url" | grep -oE 'href="[^"]+\.rpm"' | sed 's/href="//;s/"//g' | grep -v debug)
    local kernel_packages=$(echo "$packages" | grep -E '^(kernel|kernel-64kb|kernel-azure|kernel-default|kernel-kvmsmall)-[5-9]\.[0-9]')

    for pkg in $kernel_packages; do
        local version_release_arch=$(echo "$pkg" | sed -E 's/^(kernel|kernel-64kb|kernel-azure|kernel-default|kernel-kvmsmall)-//;s/\.rpm$//')
        local target_dir="$BASE_DIR/file-store/boot2os/$arch/$os@$os_version"
        [[ -f "$target_dir/vmlinuz-$version_release_arch" ]] && continue
        mkdir -p "$target_dir"

        local download_dir="$BASE_DIR/downloads/$arch/$os@$os_version/$version_release_arch"
        mkdir -p "$download_dir"
        pushd "$download_dir" >/dev/null

        echo "Downloading to: $download_dir"
        # Download related packages
        echo "$packages" | grep "$version_release_arch" | grep -v debug | while read rpkg; do
            [[ ! -f "$rpkg" ]] && wget -q "$package_url/$rpkg"
        done

        # Extract RPMs
        local temp_dir=$(mktemp -d)
        for rpm in *.rpm; do
	    echo "Extracting: $rpm"
            rpm2cpio "$rpm" | gzip -9 > $target_dir/${rpm/.rpm/.cgz}
	    rpm2cpio "$rpm" | cpio -idm -D "$temp_dir" 2>/dev/null
        done
	echo "Dir contents: $(ls -d $temp_dir/*/*)"

        # Extract vmlinuz
        local vmlinuz_path=$(find "$temp_dir" -type f -name "vmlinuz-*" | head -n1)
        if [[ -z "$vmlinuz_path" ]]; then
            rm -rf "$temp_dir"
            popd >/dev/null
            continue
        fi
        local kernel_version=$(basename "$vmlinuz_path" | sed 's/^vmlinuz-//')

        # Copy vmlinuz
        # cp "$vmlinuz_path" "$target_dir/vmlinuz-$kernel_version"
        mv $temp_dir/boot/*$kernel_version* "$target_dir"
        [[ ! -L "$target_dir/vmlinuz" ]] && ln -sf "vmlinuz-$kernel_version" "$target_dir/vmlinuz"

        # Package modules into cpio.gz
        local modules_dir="$temp_dir/lib/modules/$kernel_version"
        if [[ -d "$modules_dir" ]]; then
            (cd "$temp_dir" && { echo lib; find "lib/modules"; } | cpio -o -H newc | gzip > "$target_dir/modules-$kernel_version.cgz")
        else
            echo "Modules not found for $kernel_version"
        fi

        # Package headers and tools
        local headers_dir="$temp_dir/usr/include"
        if [[ -d "$headers_dir" ]]; then
            (cd "$temp_dir" && { echo usr; find usr/include; } | cpio -o -H newc | gzip > "$target_dir/headers-$kernel_version.cgz")
        fi

        local tools_dir="$temp_dir/usr/bin"
        if [[ -d "$tools_dir" ]]; then
            (cd "$temp_dir" && { echo usr; find usr/bin usr/sbin usr/lib usr/lib64 usr/libexec usr/share etc; } | cpio -o -H newc | gzip > "$target_dir/tools-$kernel_version.cgz")
        fi

	rm -rf "$temp_dir"
        popd >/dev/null
    done
}

# Process each OS entry
for entry in "${OS_LIST[@]}"; do
    read -r os os_version arch package_url <<< "$entry"
    case "$os" in
        openeuler|fedora|opensuse|centos) process_rpm_os "$os" "$os_version" "$arch" "$package_url" ;;
        *) echo "Unsupported OS: $os" ;;
    esac
done

echo "Done."
