#!/bin/bash
# kernel-fetch.sh - Download packages for a single OS entry

rpm_pkgnames="kernel
kernel-core
kernel-$flavor
kernel-$flavor-base
kernel-$flavor-extra
kernel-$flavor-optional
kernel-$flavor-devel
kernel-$flavor-vdso
kernel-syms
kernel-syms-$flavor
kernel-modules
kernel-modules-core
kernel-modules-extra
kernel-modules-internal
kernel-selftests-internal
bpftool
cpupower
cpupower-bench
kernel-tools
kernel-tools-libs
kernel-install-tools
kernel-tools-libs-devel
kernel-devel"

deb_pkgnames="linux-image
linux-headers
linux-tools
linux-perf
linux-bpf
linux-modules
linux-modules-extra
nic-modules
xfs-modules
btrfs-modules
bpftool"

if [ -w /srv ]; then
    BASE_DIR="/srv"
else
    BASE_DIR="$HOME/.cache/compass-ci"
fi
mkdir -p "$BASE_DIR/downloads"

# Read parameters
os="$1"
os_version="$2"
arch="$3"
package_url="$4"
flavor="${5:-default}"  # Optional flavor parameter

# Map architecture names (Debian -> Standard)
map_architecture() {
    case "$1" in
        arm64) echo "aarch64" ;;
        amd64) echo "x86_64" ;;
        *) echo "$1" ;;
    esac
}

mapped_arch=$(map_architecture "$arch")
download_dir="$BASE_DIR/downloads/$mapped_arch/$os@$os_version"
echo download_dir: $download_dir
mkdir -p "$download_dir"

# Common function to download files
list_packages() {
    local pattern="$1"
    local skip_pattern="$2"
    echo "Fetching packages from: $package_url"
    packages=$(curl -s "$package_url" | grep -oE 'href="[^"]+' | sed 's/href="//' | grep -E "$pattern" | grep -E -v "$skip_pattern")
}
    
download_packages() {
    local kernel_version=$1
    shift
    for pkg in "$@"; do
        if [[ ! -f "$download_dir/$kernel_version/$pkg" ]]; then
            echo "Downloading $pkg"
            mkdir -p "$download_dir/$kernel_version/"
            wget -q -O "$download_dir/$kernel_version/$pkg" "$package_url/$pkg" || exit
        fi
    done
}

sort_download_rpm_packages() {
    for rpm_file in $packages
    do
        local kernel_version=$(echo "$rpm_file" | sed -E "s/^($pkgpattern)-//;s/\.rpm$//")
        download_packages $kernel_version $rpm_file
    done
}

sort_download_deb_packages() {
    declare -A package_map
    declare -A max_versions

    for deb_file in $packages
    do
        local deb_file="${BASH_REMATCH[1]}"

        # Determine package type
        local pkg_type=""
        if [[ "$deb_file" =~ ^($pkgpattern)-[0-9] ]]; then
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
    done

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

        packages_to_download=()
        for image_entry in "${package_map[@]}"
        do
            local image_full_version=$(echo "$image_entry" | cut -d ' ' -f1)
            if [[ "$image_full_version" != "$full_version" ]]; then continue; fi
            packages_to_download+=( $(echo "$image_entry" | cut -d ' ' -f2) )
        done
        if [[ -z "$packages_to_download" ]]; then continue; fi

        # Download packages
        echo packages_to_download: "${packages_to_download[@]}"
        download_packages $full_version "${packages_to_download[@]}"
    done
}

case "$os" in
    openeuler|fedora|opensuse|centos|rocky)
        # RPM-based processing
        pkgpattern=$(echo "$rpm_pkgnames" | tr '\n' '|' | sed 's/|$//')
        list_packages "^($pkgpattern)-[4-9]\.[0-9].*\.rpm" "(debug|obs)"
        sort_download_rpm_packages
        ;;
    debian|ubuntu)
        # DEB-based processing
        pkgpattern=$(echo "$deb_pkgnames" | tr '\n' '|' | sed 's/|$//')
        list_packages "^($pkgpattern).*_$arch.deb" "(-uc-|unsigned|dbg|bpo|~exp)"
        sort_download_deb_packages
        ;;
    *)
        echo "Unsupported OS: $os"
        exit 1
        ;;
esac

echo "Fetch completed for $os $os_version $arch"

# vim:set ts=4 sw=4 et:
