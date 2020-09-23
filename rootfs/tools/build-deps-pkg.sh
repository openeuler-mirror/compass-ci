#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+
# Copyright (c) 2020 Huawei Technologies Co., Ltd. All rights reserved.

# Exclude 'dev' or some files that do not need to perform cci-depends.
suffix_detect()
{
	[ ${1##*.} != $1 ] || [ ${1##*-} == 'dev' ]
}

submit_job()
{
	command submit "$CCI_SRC/rootfs/build-deps-pkg.yaml"
}

deps_generate_yaml()
{
	export suite='cci-depends'

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
	export suite='cci-makepkg'

	for benchmark
	do
		[ -f "$LKP_SRC/pkg/$benchmark/PKGBUILD" ] || continue

		export benchmark
		submit_job
	done
}

set_vars()
{
	local work_dir=$(pwd)
	local os_path=${work_dir##*/rootfs/}
	local os_array=($(echo "$os_path" | tr '/' ' '))

	[[ "${work_dir}" == "${os_path}" ]] && {
		echo "error: script execution path error"
		echo "cd ${CCI_SRC}/rootfs/\$os_mount/\$os/\$os_arch/\$os_version; ./${0}"
		exit 1
	}

	[[ "${#os_array[@]}" == 4 ]] || {
		echo "error: expect 4 parameters, found ${#os_array[@]}"
		exit 2
	}

	export os_mount="${os_array[0]}"
	export os="${os_array[1]}"
	export os_arch="${os_array[2]}"
	export os_version="${os_array[3]}"
}

main()
{
	set_vars

	if [ "$#" -gt 0 ]; then
		[[ "$0" == 'build-depends' ]] && deps_generate_yaml "$@"
		[[ "$0" == 'build-makepkg' ]] && pkg_generate_yaml "$@"
	else
		[[ "$0" == 'build-depends' ]] && deps_generate_yaml $(ls "$LKP_SRC"/distro/depends)
		[[ "$0" == 'build-makepkg' ]] && pkg_generate_yaml $(ls "$LKP_SRC"/pkg)
	fi
}

main "$@"
