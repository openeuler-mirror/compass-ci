#!/bin/bash

# OS list: Format - "OS_NAME OS_VERSION ARCH PACKAGE_URL"
SUSE_OS_LIST=(
    # openSUSE
    "opensuse   15.6       x86_64     https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/x86_64/"
    "opensuse   15.6       aarch64    https://mirrors.tuna.tsinghua.edu.cn/opensuse/distribution/leap/15.6/repo/oss/aarch64/"
)

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

    # CentOS Stream
    # problem: no kernel image here
    # "centos     9          x86_64     https://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/Packages/"
    # "centos     9          aarch64    https://mirror.stream.centos.org/9-stream/AppStream/aarch64/os/Packages/"

    # Fedora
    # problem: rpm2cpio wont extract /boot dir in kernel-core-6.13.5-200.fc41.x86_64.rpm
    "fedora     41         aarch64    http://mirrors.163.com/fedora/releases/41/Everything/aarch64/os/Packages/k/"
    "fedora     41         x86_64     http://mirrors.163.com/fedora/releases/41/Everything/x86_64/os/Packages/k/"
    "fedora     41         aarch64    http://mirrors.163.com/fedora/updates/41/Everything/aarch64/Packages/k/"
    "fedora     41         x86_64     http://mirrors.163.com/fedora/updates/41/Everything/x86_64/Packages/k/"

    # Rocky Linux
    # same problem with Fedora
    "rocky      9.5        aarch64    http://mirrors.163.com/rocky/9.5/BaseOS/aarch64/os/Packages/k/"
    "rocky      9.5        x86_64     http://mirrors.163.com/rocky/9.5/BaseOS/x86_64/os/Packages/k/"

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

# Map architecture names (Debian -> Standard)
map_architecture() {
    case "$1" in
        arm64) echo "aarch64" ;;
        amd64) echo "x86_64" ;;
        *) echo "$1" ;; # Default to the input if no mapping exists
    esac
}

# Function to process kernel files, modules, headers, and tools
process_kernel_files() {
    local temp_dir="$1"
    local target_dir="$2"
    local kernel_version="$3"

    # fixup for fedora/rocky
    # example: /lib/modules/5.14.0-503.26.1.el9_5.aarch64/vmlinuz
    [[ -f "$temp_dir/lib/modules/$kernel_version/vmlinuz" ]] &&
    [[ ! -e "$temp_dir/boot/vmlinuz-$kernel_version" ]] && {
        mkdir "$temp_dir/boot/"
        for i in vmlinuz System.map config symvers.xz symvers.gz vmlinuz-virt.efi
        do
            test -f "$temp_dir/lib/modules/$kernel_version/$i" &&
            mv "$temp_dir/lib/modules/$kernel_version/$i" "$temp_dir/boot/$i-$kernel_version"
        done
    }

    # Copy boot dir
    mv $temp_dir/boot/*$kernel_version* "$target_dir" || exit
    [[ ! -L "$target_dir/vmlinuz" ]] && {
        test -f "$target_dir/vmlinux-$kernel_version.gz" && ln -sf "vmlinux-$kernel_version.gz" "$target_dir/vmlinuz"
        test -f "$target_dir/vmlinuz-$kernel_version" && ln -sf "vmlinuz-$kernel_version" "$target_dir/vmlinuz"
    }

    # Package modules
    local modules_dir="$temp_dir/usr/lib/modules/$kernel_version"
    if [[ -d "$modules_dir" ]]; then
        (cd "$temp_dir" && { echo usr; find "usr/lib"; } | cpio -o -H newc | gzip -9 > "$target_dir/modules-$kernel_version.cgz")
    else
        # Package modules into cpio.gz
        local modules_dir="$temp_dir/lib/modules/$kernel_version"
        if [[ -d "$modules_dir" ]]; then
            (cd "$temp_dir" && { find "lib"; } | cpio -o -H newc | gzip -9 > "$target_dir/modules-$kernel_version.cgz")
        fi
    fi

    # Package headers
    local headers_dir="$temp_dir/usr/include"
    if [[ -d "$headers_dir" ]]; then
        (cd "$temp_dir" && { echo usr; find usr/include; } | cpio -o -H newc | gzip -9 > "$target_dir/headers-$kernel_version.cgz")
    fi

    # Package tools
    local tools_dir="$temp_dir/usr/bin"
    if [[ -d "$tools_dir" ]]; then
        local usr_dirs=$(show_exist_dirs usr/bin usr/sbin usr/lib usr/lib64 usr/libexec usr/share etc)
        (cd "$temp_dir" && { echo usr; find $usr_dirs; } | cpio -o -H newc | gzip -9 > "$target_dir/tools-$kernel_version.cgz")
    fi
}

# Function to process RPM-based OS
process_rpm_os() {
    local os="$1" os_version="$2" arch="$3" package_url="$4"
    echo "Processing RPM OS: $os $os_version $arch"

    local pkgnames="kernel
kernel-core
kernel-$flavor
kernel-$flavor-base
kernel-$flavor-extra
kernel-$flavor-optional
kernel-$flavor-devel
kernel-syms
kernel-modules
kernel-modules-core
kernel-modules-extra
kernel-modules-internal
kernel-selftests-internal
kernel-tools-libs
kernel-install-tools
kernel-tools-libs-devel
kernel-devel"

    local pkgpattern=$(echo "$pkgnames" | tr '\n' '|' | sed 's/|$//')

    # Fetch package listing
    local packages=$(curl -s "$package_url" | grep -oE 'href="[^"]+\.rpm"' | sed 's/href="//;s/"//g' | grep -v -e debug -e obs)
    local kernel_packages=$(echo "$packages" | grep -E "^($pkgpattern)-[5-9]\.[0-9]")

    for pkg in $kernel_packages; do
        local version_release_arch=$(echo "$pkg" | sed -E "s/^($pkgpattern)-//;s/\.rpm$//")
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
            local files=$(rpm -q -l -p $rpm 2>/dev/null)
            if echo "$files" |grep -q -E -e 'lib/modules/[0-9]\.[0-9]+\.[0-9]' -e 'boot/(kernel|vmlinu[xz])-[0-9]\.[0-9]+\.[0-9]'
            then
                rpm2cpio "$rpm" | cpio -idm -D "$temp_dir" 2>/dev/null
            else
                rpm2cpio "$rpm" | gzip -9 > "$target_dir/${rpm/.rpm/.cgz}"
            fi
        done
        echo "Dir contents: $(ls -d $temp_dir/*/*)"

        # Process kernel files
        for kernel_version in $({ ls $temp_dir/lib/modules; ls $temp_dir/usr/lib/modules; } 2>/dev/null | sort -u | grep -E '[0-9].[0-9]+.[0-9]+')
        do
            process_kernel_files "$temp_dir" "$target_dir" "$kernel_version"
        done

        rm -rf "$temp_dir"
        popd >/dev/null
    done
}

# Function to process Debian-based OS
process_deb_os() {
    local os="$1" os_version="$2" arch="$3" package_url="$4"
    echo "Processing Debian OS: $os $os_version $arch"

    # Fetch HTML content
    local html_content=$(curl -s "$package_url")
    # local html_content=$(cat /tmp/index.html)
    # set -x

    # Extract .deb filenames from HTML
    declare -A package_map
    declare -A max_versions

    # Parse HTML content for .deb files
    while IFS= read -r line; do
        # Extract href value from <a> tags
        if [[ "$line" =~ \<a\ href=\"([^\"]+\.deb)\"\> ]]; then
            local deb_file="${BASH_REMATCH[1]}"

            # Skip unwanted packages
            if [[ "$deb_file" =~ (-uc-|unsigned|dbg|bpo|~exp) ]]; then
                continue
            fi

            [[ "${deb_file#*$arch}" = "$deb_file" ]] && continue

            # Determine package type
            local pkg_type=""
            if [[ "$deb_file" =~ ^(linux-image|linux-headers|linux-tools|linux-perf|linux-bpf|linux-modules|linux-modules-extra|nic-modules|xfs-modules|btrfs-modules|bpftool)-[0-9] ]]; then
                pkg_type="${BASH_REMATCH[1]}"
            else
                continue
            fi

            # Extract version and variant
            if [[ "$deb_file" =~ -([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)(-[^_]+)?_ ]] ||
               [[ "$deb_file" =~ -([0-9]+\.[0-9]+\.[0-9]+)(-[^_]+)?_ ]]; then
                local upstream_version="${BASH_REMATCH[1]}"
                local variant="${BASH_REMATCH[2]}"
                local full_version="$upstream_version${variant}"

                # Extract major version (e.g., 6.8 from 6.8.0-45)
                local major_version=$(echo "$upstream_version" | cut -d '.' -f1-2)

                # Skip old kernels
                [[ "$major_version" =~ ^[6-9] ]] || continue

                # Update max_versions for this major_version:variant
                local key="$major_version:$variant"
                if [[ -z "${max_versions[$key]}" ]] || [[ "$upstream_version" > "${max_versions[$key]}" ]]; then
                    max_versions["$key"]="$upstream_version"
                fi

                # Store in package_map
                package_map["$key:$pkg_type"]="$full_version $deb_file"
            fi
        fi
    done <<< "$html_content"

    # Process each major_version:variant
    for key in "${!max_versions[@]}"; do
        local major_version_variant="$key"
        local major_version=$(echo "$key" | cut -d: -f1)
        local variant=$(echo "$key" | cut -d: -f2)
        local upstream_version="${max_versions[$key]}"
        local full_version="$upstream_version${variant}"

        # Collect package entries
        local image_entry="${package_map["$key:linux-image"]}"
        local modules_entry="${package_map["$key:linux-modules"]}"

        # Check if image package exists and matches upstream_version
        if [[ -z "$image_entry$modules_entry" ]]; then continue; fi

        local packages_to_download=()
        for image_entry in "${package_map[@]}"
        do
            local image_full_version=$(echo "$image_entry" | cut -d ' ' -f1)
            if [[ "$image_full_version" != "$full_version" ]]; then continue; fi
            packages_to_download+=( $(echo "$image_entry" | cut -d ' ' -f2) )
        done
        if [[ -z "$packages_to_download" ]]; then continue; fi

        # Download packages
        echo "${packages_to_download[@]}"

        # Prepare directories
        mapped_arch=$(map_architecture "$arch")
        local target_dir="$BASE_DIR/file-store/boot2os/$mapped_arch/$os@$os_version"
        local download_dir="$BASE_DIR/downloads/$mapped_arch/$os@$os_version/$full_version"
        mkdir -p "$target_dir" "$download_dir"
        pushd "$download_dir" >/dev/null
        echo "Downloading to: $download_dir"

        for deb_file in "${packages_to_download[@]}"; do
            local deb_url="$package_url/$deb_file"
            [[ ! -f "$deb_file" ]] && wget -q "$deb_url"
        done

        [[ "$os" = "ubuntu" ]] && {
            # ubuntu have to download these from 2 different urls, then proceed
            ls linux-image-* linux-modules-* >/dev/null 2>/dev/null || continue
        }

        # Extract and process packages
        local temp_dir=$(mktemp -d)
        for deb in *.deb; do
            echo "Extracting $deb"
            ar x "$deb" --output="$temp_dir"
            data_tar=$(find "$temp_dir" -maxdepth 1 -name 'data.tar.*' | head -n1)
            [[ -n "$data_tar" ]] && { tar -xf "$data_tar" -C "$temp_dir"; rm $data_tar; }
            data_tar=$(find "$temp_dir" -maxdepth 1 -name 'data.tar' | head -n1)
            [[ -n "$data_tar" ]] && { tar -xf "$data_tar" -C "$temp_dir"; rm $data_tar; }
        done

        # Process kernel files
        for kernel_version in $({ ls lib/modules; ls usr/lib/modules; } 2>/dev/null | sort -u | grep -E '[0-9].[0-9]+.[0-9]+')
        do
            process_kernel_files "$temp_dir" "$target_dir" "$kernel_version"
        done

        rm -rf "$temp_dir"
        popd >/dev/null
    done
}

show_exist_dirs() {
    # Loop through each directory passed as an argument
    for dir in "$@"; do
        # Check if the directory exists
        if [ -d "$dir" ]; then
            # If it exists, print it
            echo "$dir"
        fi
    done
}

process_os_list() {
    # Process each OS entry
    for entry in "$@"; do
        read -r os os_version arch package_url <<< "$entry"
        case "$os" in
            openeuler|fedora|opensuse|centos|rocky) process_rpm_os "$os" "$os_version" "$arch" "$package_url" ;;
            debian|ubuntu) process_deb_os "$os" "$os_version" "$arch" "$package_url" ;;
            *) echo "Unsupported OS: $os" ;;
        esac
    done
}

process_os_list "${OS_LIST[@]}"

flavor=default
process_os_list "${SUSE_OS_LIST[@]}"
flavor=64kb
process_os_list "${SUSE_OS_LIST[@]}"
flavor=kvmsmall
process_os_list "${SUSE_OS_LIST[@]}"
# flavor=azure
# process_os_list "${SUSE_OS_LIST[@]}"

echo "Done."
# vim:set ts=4 sw=4 et:
