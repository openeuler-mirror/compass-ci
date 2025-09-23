#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

set -o pipefail
shopt -s nullglob

# Configuration and environment setup
init_environment() {
    : "${LKP_SRC:=/c/lkp-tests}"
    : "${job_id:=$$}"
    : "${docker_image:=centos:7}"
    : "${hostname:=dc-8g-1}"
    : "${host_dir:=${HOME}/.cache/compass-ci/provider/hosts/${hostname}}"
    : "${log_file:=${HOME}/.cache/compass-ci/provider/logs/${hostname}}"

    export LKP_SRC job_id docker_image hostname host_dir log_file
    SCRIPT_DIR=$(dirname "$(realpath "$0")")
    export SCRIPT_DIR

    # Source library functions
    # shellcheck source=/dev/null
    . "${LKP_SRC}/lib/yaml.sh"
}

parse_host_metadata() {
    local host_file="${LKP_SRC}/hosts/${host}"

    [[ -f "${host_file}" ]] || {
        echo "Error: Host configuration file ${host_file} not found" >&2
        return 1
    }

    # Set host parameters
    nr_cpu=${nr_cpu:-$(grep '^nr_cpu: ' "${host_file}" | cut -f2 -d' ')}
    memory=${memory:-$(grep '^memory: ' "${host_file}" | cut -f2 -d' ')}
}

determine_host_group() {
    if [[ "${hostname}" =~ ^(.*)-[0-9]+$ ]]; then
        tbox_group=${BASH_REMATCH[1]}
    else
        tbox_group=${hostname}
    fi
    host=${tbox_group%.*}
}

check_container_runtime() {
    if [[ -n "$OCI_RUNTIME" ]]; then
        container_runtime=$OCI_RUNTIME
    else
        container_runtime=$(command -v podman || command -v docker || true)
    fi
    [[ -n "${container_runtime}" ]] || {
        echo "Error: No container runtime (podman/docker) found" >&2
        exit 1
    }
    export container_runtime
}

set_resource_limits() {
    # Set default resource limits
    memory_minimum=${memory_minimum:-8}
    memory="${memory}g"
    nr_cpu=${cpu_minimum:-${nr_cpu}}
}

configure_ccache() {
    [[ "${ccache_enable}" != "True" ]] && return 0

    local ccache_container
    ccache_container=$($container_runtime ps --format '{{.Names}}' | grep -m1 'k8s_ccache_ccache' || true)
    volumes_from=${ccache_container:-ccache}
    CCACHE_DIR=/etc/.ccache
    export CCACHE_DIR
}

setup_file_paths() {
    busybox_path="${BASE_DIR}/file-store/busybox/$(arch)"
    [[ -e "${busybox_path}/busybox" ]] || busybox_path="/srv/file-store/busybox/$(arch)"
    export busybox_path
}

configure_networking() {
    if command -v kubectl >/dev/null; then
        squid_host=$(kubectl get svc -n ems1 -o jsonpath="{.items[?(@.metadata.name=='squid-${HOSTNAME}')].spec.clusterIP}" || true)
    fi
    export SQUID_HOST=${squid_host}
}

build_base_command() {
    container_cmd=(
        "${container_runtime}" run
        --rm
        --name "${hostname}"
        --hostname "${host}.compass-ci.net"
        -m "${memory}"
        --net=host
        --log-driver json-file
        --log-opt max-size=10m
        --oom-score-adj="-1000"
    )

    [[ -n "${nr_cpu}" && "$nr_cpu" -ne 0 ]] && container_cmd+=(--cpus "${nr_cpu}")
}

add_volume_mounts() {
    container_cmd+=(
        -v "${SCRIPT_DIR}/bin/entrypoint.sh:/root/bin/entrypoint.sh:ro"
        -v "${busybox_path}:/opt/busybox:ro"
        -v "${host_dir}/lkp/cpio-for-guest:/lkp/cpio-for-guest"
    )

    # Add package directories
    for dir in "${host_dir}"/opt/*/; do
        [[ -d "${dir}" ]] || continue
        container_cmd+=(-v "${dir}:${dir#$host_dir}:ro")
    done
}

add_runtime_specific_options() {
    if [[ "${container_runtime#*docker}" != "$container_runtime" ]]; then
        [[ -n "$build_mini_docker" ]] &&
        container_cmd+=(
            -v /var/run/docker.sock:/var/run/docker.sock
            -v /usr/bin/docker:/usr/bin/docker:ro
        )
    else
        container_cmd+=(--replace)
    fi

    [[ $(id -u) -eq 0 ]] && container_cmd+=(--privileged -v /sys/kernel/debug:/sys/kernel/debug:ro)
    [[ -n "${volumes_from}" ]] && container_cmd+=(--volumes-from "${volumes_from}")
}

setup_package_cache() {
    [[ -z "${PACKAGE_CACHE_DIR}" ]] && return 0

    case "${os}" in
        debian|ubuntu)
            mkdir -p "${PACKAGE_CACHE_DIR}/${osv}/archives"
            mkdir -p "${PACKAGE_CACHE_DIR}/${osv}/lists"
            container_cmd+=(
                -v "${PACKAGE_CACHE_DIR}/${osv}/archives:/var/cache/apt/archives"
                -v "${PACKAGE_CACHE_DIR}/${osv}/lists:/var/lib/apt/lists"
            )
            ;;
        openeuler|centos|rhel|fedora)
            mkdir -p "${PACKAGE_CACHE_DIR}/${osv}"
            container_cmd+=(-v "${PACKAGE_CACHE_DIR}/${osv}:/var/cache/dnf")
            ;;
    esac
}

setup_execution_environment() {
    [[ -n "${CCI_SRC}" ]] && container_cmd+=(
        -e "CCI_SRC=/c/compass-ci"
        -v "${CCI_SRC}:/c/compass-ci:ro"
    )

    [[ -d /srv/git ]] && container_cmd+=(-v "/srv/git:/srv/git:ro")
    [[ -n "${cache_dirs}" ]] && container_cmd+=(-v "${CACHE_DIR}:/srv/cache")
}

log_container_start() {
    mkdir -p "$(dirname "${log_file}")"
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    cat <<-EOF >> "${log_file}"
		${start_time} starting CONTAINER
		job_id ${job_id}
		result_root ${result_root}

	EOF
    export startup_time=$(date +%s)
}

log_container_completion() {
    local end_time=$(date +%s)
    export dc_run_time=$((end_time - startup_time))
    local duration=$((dc_run_time / 60))
    printf "\nTotal CONTAINER duration: %d minutes\n" "${duration}" >> "${log_file}"
}

execute_container() {
    echo "${container_cmd[@]}" | sed 's/  *-/\n\t-/g'
    echo -e "\t$docker_image" /root/bin/entrypoint.sh

    "${container_cmd[@]}" "$docker_image" /root/bin/entrypoint.sh 2>&1 | \
        awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; fflush(); }' | \
        tee -a "${log_file}"
    return ${PIPESTATUS[0]}
}

mount_docker_volume() {
    local dir="$1"
    local option="$2"

    for rootdir in lkp opt; do
        for d in "$dir"/"$rootdir"/*/; do
            if [ -d "$d" ]; then
                dest_dir="${d##"$dir/"}"
                container_cmd+=(-v "$d:/${dest_dir}:$option")
            fi
        done
    done
}

unpack_cache_cpio() {
    local file="$1"
    local dir="$2"
    local option="$3"

    if [ -e "$dir" ]; then
        touch "$dir"
        mount_docker_volume "$dir" "$option"
        return 0
    else
        mkdir -p "$dir"
        if gzip -dc "$file" | cpio -idu --quiet --directory "$dir"; then
            mount_docker_volume "$dir" "$option"
            return 0
        else
            return 1
        fi
    fi
}

unpack_cpio_in_host() {
    local file="$1"
    local resolved_file

    if [ -L "$file" ]; then
        resolved_file=$(readlink -f "$file")
    else
        resolved_file="$file"
    fi

    if [[ $(basename "$resolved_file") == "job.cgz" ]]; then
        return 1
    fi

    if [[ "$container_runtime" =~ podman$ ]]; then
        if [[ "$resolved_file" =~ /file-store/lkp_src/base/(.*)\.cgz$ ]]; then
            local dir="${PKG_STORE_DIR}/2-lkp_commit/${BASH_REMATCH[1]}"
            unpack_cache_cpio "$resolved_file" "$dir" "O"
            return $?
        fi
    fi

    if [[ "$resolved_file" =~ /file-store/ss/pkgbuild/(.*)\.cgz$ ]]; then
        local matched="${BASH_REMATCH[1]}"
        if ! gzip -dc "$resolved_file" | cpio -it | grep -F '/' | grep -m1 -qv -e '^lkp/' -e '^opt/'; then
            local dir="${PKG_STORE_DIR}/5-pkgbuild/${matched}"
            unpack_cache_cpio "$resolved_file" "$dir" "ro"
            return $?
        fi
    fi

    return 1
}

unpack_cpio_in_guest() {
    local file="$1"
    local initrd_dir="${host_dir}/lkp/cpio-for-guest"

    mkdir -p "$initrd_dir"
    cp -L -l "$file" "$initrd_dir/$(basename $file)"
}

setup_package_store() {
    for file in "${host_dir}"/cpio-all/*; do
        if unpack_cpio_in_host "$file"; then
            continue
        fi
        unpack_cpio_in_guest "$file"
    done
}

main() {
    init_environment
    determine_host_group
    parse_host_metadata
    check_container_runtime
    configure_ccache
    set_resource_limits
    setup_file_paths
    configure_networking

    build_base_command
    add_volume_mounts
    add_runtime_specific_options

    setup_execution_environment
    setup_package_cache # rpm/deb
    setup_package_store # cpio rootfs

    log_container_start
    execute_container "${full_command}"
    container_return_code=$?
    log_container_completion

    # Signal job completion
    JOB_DONE_FIFO_PATH=${JOB_DONE_FIFO_PATH:-/tmp/job_completion_fifo}
    if [ $container_return_code -ne 0 ] && [ $dc_run_time -le 1 ]; then
      echo "abort: ${job_id}" >> "${JOB_DONE_FIFO_PATH}"
    else
      echo "done: ${job_id}" >> "${JOB_DONE_FIFO_PATH}"
    fi

}

main "$@"
