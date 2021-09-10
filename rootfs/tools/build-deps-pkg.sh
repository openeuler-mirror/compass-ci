#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# Exclude 'dev' or some files that do not need to perform cci-depends.

WORK_DIR=$(dirname $(readlink -f "$0"))
cd "$WORK_DIR" || exit

set_suite=''
os_flag=''
packages=''

usage()
{
	cat <<-EOF
Usage: build-all.sh [-s set_suite] [-o os_flag] [-p packages]

options:
    -s set_suite  set suite, select one from two, default cci-depends and cci-makepkg
    -o os_flag    eg: 'nfs_centos_aarch64_7.6.1810 container_openeuler_...', default \$(cat ./os_var_file)
    -p packages   package name, default all
EOF
	exit 4
}

while getopts "s:o:p:" opt
do
	case "$opt" in
		s ) set_suite="$OPTARG"; ;;
		o ) os_flag="$OPTARG"; ;;
		p ) packages="$OPTARG"; ;;
		? ) usage; ;;
	esac
done

suffix_detect()
{
	[ ${1##*.} != $1 ] || [ ${1##*-} == 'dev' ]
}

blocklist_detect()
{
	if [ ${suite} = "cci-depends" ]; then
		grep -qFx $1 ./blocklist/deps/${os_mount}/${os}/${os_version}/blocklist && exit
	else
		grep -qFx $1 ./blocklist/pkg/${os_mount}/${os}/${os_version}/blocklist && exit
	fi
}

submit_job()
{
	if [ ${os_mount} != "container" ]; then
		command "$LKP_SRC/sbin/submit" "./build-deps-pkg.yaml"
	else
		command "$LKP_SRC/sbin/submit" "./build-deps-pkg-dc.yaml"
	fi
}

deps_generate_yaml()
{
	for benchmark
	do
		suffix_detect "$benchmark" && continue
		[ -f "$LKP_SRC/distro/depends/$benchmark" ] || continue

		export benchmark
		submit_job
	done
}

pkg_generate_yaml()
{
	for benchmark
	do
		[ -f "$LKP_SRC/pkg/$benchmark/PKGBUILD" ] || continue

		export benchmark
		submit_job
	done
}

set_vars_env()
{
		local os_array=($(echo "$1"|tr '_' ' '))
		[[ "${#os_array[@]}" == 4 ]] || {
			echo "$1 :expect 4 parameters, found ${#os_array[@]}"
			exit 3
		}

		export os_mount=${os_array[0]}
		export os=${os_array[1]}
		export os_arch=${os_array[2]}
		export os_version=${os_array[3]}
		export docker_image=${os_array[1]}:${os_array[3]}
}

build_deps()
{
	export suite='cci-depends'

	if [ -n "$packages" ]; then
		blocklist_detect $packages
		deps_generate_yaml $packages
	else
		deps_generate_yaml $(ls "$LKP_SRC"/distro/depends | \
			grep -xvf ./blocklist/deps/${os_mount}/${os}/${os_version}/blocklist)
	fi
}

build_pkg()
{
	export suite='cci-makepkg'

	if [ -n "$packages" ]; then
		blocklist_detect $packages
		pkg_generate_yaml $packages
	else
		pkg_generate_yaml $(ls "$LKP_SRC"/pkg | \
			grep -xvf ./blocklist/pkg/${os_mount}/${os}/${os_version}/blocklist)
	fi
}

build()
{
	for os_argv in "$@"
	do
		set_vars_env "$os_argv"

		if [ -n "$set_suite" ]; then
			[[ $set_suite == 'cci-depends' ]] && build_deps
			[[ $set_suite == 'cci-makepkg' ]] && build_pkg
		else
			build_deps
			build_pkg
		fi
	done
}

set_os_vars()
{
	if [ -z "$os_flag" ]; then
		[ -s "./os_var_file" ] || {
			echo "error: 'os_var_file' file does not exist or content is empty"
			exit 1
		}

		build $(cat ./os_var_file)
	else
		build $os_flag
	fi
}

set_os_vars
