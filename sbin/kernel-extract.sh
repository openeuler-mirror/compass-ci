#!/bin/bash
# kernel-extract.sh - Process downloaded packages in given directories

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <directory1> [directory2 ...]"
    echo directory example: ~/.cache/compass-ci/downloads/aarch64/opensuse@15.6/6.4.0-150600.21.1.aarch64
    exit 1
fi

set_vars() {
    # Example download_dir
    # download_dir=~/.cache/compass-ci/downloads/aarch64/opensuse@15.6/6.4.0-150600.21.1.aarch64

    # Extract version
    version=$(basename "$download_dir")
    echo "Kernel Version: $version"

    # Extract os and os_version
    osv=$(basename "$(dirname "$download_dir")")
    os=$(echo "$osv" | cut -d '@' -f 1)
    os_version=$(echo "$osv" | cut -d '@' -f 2)
    echo "OS: $os"
    echo "OS Version: $os_version"

    # Extract arch
    arch=$(basename "$(dirname "$(dirname "$download_dir")")")
    echo "Architecture: $arch"

    BASE_DIR="${download_dir%/downloads/*}"
    target_dir="$BASE_DIR/file-store/boot2os/$arch/$osv"
    echo "BASE_DIR: $BASE_DIR"
    echo "Target dir: $target_dir"
}

show_exist_dirs() {
    for dir in "$@"; do
        [ -d "$dir" ] && echo "$dir"
    done
}

process_kernel_files() {
    local temp_dir="$1"
    local kernel_version="$2"
    
    # Fix Fedora/Rocky directory structure
    # example: /lib/modules/5.14.0-503.26.1.el9_5.aarch64/vmlinuz
    if [[ -f "$temp_dir/lib/modules/$kernel_version/vmlinuz" ]]; then
        mkdir "$temp_dir/boot/"
        for i in vmlinuz System.map config symvers.xz symvers.gz vmlinuz-virt.efi
        do
            test -f "$temp_dir/lib/modules/$kernel_version/$i" &&
            mv "$temp_dir/lib/modules/$kernel_version/$i" "$temp_dir/boot/$i-$kernel_version"
        done
    fi

    # Copy boot dir
    mv $temp_dir/boot/*$kernel_version* "$target_dir" || exit
    [[ ! -L "$target_dir/vmlinuz" ]] && {
        # opensuse has Image
        test -f "$target_dir/Image-$kernel_version"   && ln -sf "Image-$kernel_version" "$target_dir/vmlinuz"
        test -f "$target_dir/vmlinuz-$kernel_version" && ln -sf "vmlinuz-$kernel_version" "$target_dir/vmlinuz"
    }

    # Package modules
    local modules_dir="$temp_dir/usr/lib/modules/$kernel_version"
    if [[ -d "$modules_dir" ]]; then
        convert_zstd "$modules_dir"
        (cd "$temp_dir" && { echo usr; find "usr/lib"; } | cpio -o -H newc | gzip -9 > "$target_dir/modules-$kernel_version.cgz")
    else
        # Package modules into cpio.gz
        local modules_dir="$temp_dir/lib/modules/$kernel_version"
        if [[ -d "$modules_dir" ]]; then
            convert_zstd "$modules_dir"
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

# opensuse has ko.zst, however has no zstd tool in docker userland
# convert them to ko.xz, which can be handled by busybox xz
convert_zstd() {
    local modules_dir="$1"

    # Check if the directory exists
    if [ ! -d "$modules_dir" ]; then
        echo "Error: Directory '$modules_dir' does not exist."
        return 1
    fi

    # Step 1: Update modules.dep to replace .ko.zst with .ko.xz
    local modules_dep="$modules_dir/modules.dep"
    if [ -f "$modules_dep" ]; then
        grep -q -F '.ko.zst:' "$modules_dep" || return 0

        echo "Updated $modules_dep from .ko.zst to .ko.xz"
        sed -i 's/\.ko\.zst/.ko.xz/g' "$modules_dep"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to update $modules_dep."
            return 1
        fi
    else
        echo "Warning: $modules_dep not found. Skipping update."
    fi

    # Step 2: Recursively find and process *.ko.zst files
    find "$modules_dir" -type f -name '*.ko.zst' | while read -r zst_file; do
        # echo "Processing $zst_file..."

        # Uncompress .zst file
        zstd -qd "$zst_file" -o "${zst_file%.zst}"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to uncompress $zst_file."
            return 1
        fi

        # Compress to .xz file
        xz "${zst_file%.zst}"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to compress ${zst_file%.zst} to .xz."
            return 1
        fi

        # Remove the original .zst file
        rm "$zst_file"
        # echo "Converted $zst_file to ${zst_file%.zst}.xz"
    done

    # echo "Conversion completed successfully."
    return 0
}

extract_rpm() {
    for rpm in "$download_dir"/*.rpm; do
        echo "Extracting: $rpm"
        local files=$(rpm -q -l -p $rpm 2>/dev/null)
        if echo "$files" |grep -q -E -e 'lib/modules/[0-9]\.[0-9]+\.[0-9]' -e 'boot/(kernel|vmlinu[xz])-[0-9]\.[0-9]+\.[0-9]'
        then
            rpm2cpio "$rpm" | cpio -idm -D "$temp_dir" 2>/dev/null
        else
            rpm2cpio "$rpm" | gzip -9 > "$target_dir/$(basename $rpm .rpm).cgz"
        fi
    done
    echo "Dir contents:"
    ls -d $temp_dir/*/*
    ls -d $temp_dir/lib/modules/*
}

extract_deb() {
    for deb in "$download_dir"/*.deb; do
        echo "Extracting $deb"
        ar x "$deb" --output="$temp_dir" || exit
        data_tar=$(find "$temp_dir" -maxdepth 1 -name 'data.tar.*' | head -n1)
        [[ -n "$data_tar" ]] && { tar -xf "$data_tar" -C "$temp_dir"; rm $data_tar; }
        data_tar=$(find "$temp_dir" -maxdepth 1 -name 'data.tar' | head -n1)
        [[ -n "$data_tar" ]] && { tar -xf "$data_tar" -C "$temp_dir"; rm $data_tar; }
    done
}

process_versions() {
    for kernel_version in $(ls "$temp_dir/lib/modules" 2>/dev/null); do
        process_kernel_files "$temp_dir" "$kernel_version"
    done
}

# Function to process a single directory
process_directory() {
    local dir="$1"

    # Check if the directory exists
    if [[ ! -d "$dir" ]]; then
        echo "Directory not found: $dir"
        return 1
    fi

    # Convert to absolute path
    download_dir=$(realpath "$dir")

    echo "Processing directory: $download_dir"
    (
        cd "$download_dir" || exit
        process_one
    )
}

process_one() {
    # Determine OS vars based on download directory
    set_vars

    mkdir -p "$target_dir"
    temp_dir=$(mktemp -d)

    case "$os" in
        openeuler|fedora|opensuse|centos|rocky)
            extract_rpm
            process_versions
            ;;
        debian|ubuntu)
            extract_deb
            process_versions
            ;;
        *) echo "Unsupported OS type: $os"; exit 1 ;;
    esac

    rm -rf "$temp_dir"

    echo "Extraction completed for $download_dir"
}

# Iterate over all provided directories
for input_dir in "$@"; do
    process_directory "$input_dir"
done

# vim:set ts=4 sw=4 et:
