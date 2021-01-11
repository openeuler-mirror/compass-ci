# Use the tool to create a new nfsroot for os

## Usage:
        ./run <src_docker_file_abspath> <dst_rootfs_new_abspath>

        src_docker_file_abspath: source .tar.xz file absolute path with suffix: [ tar.xz ].
        dst_rootfs_new_abspath: destination absolute path to create for rootfs.

## Example:
	./run /tmp/openEuler-docker/openEuler-docker.aarch64.tar.xz /tmp/openeuler-rootfs/
	# Please ensure $HOME/.config/compass-ci/rootfs-passwd exists.

## Some configuration items:
	./packages-to-install
   	# If you want to pre-install the software, you can write the package names in ./packages-to-install.

	$HOME/.config/compass-ci/rootfs-passwd
   	# Set the password for the image into this file.
