# Use the tool to create a new openeuler-${os_version} initramfs image.

Usage:
       cd ${CCI_SRC}/rootfs/initramfs/openeuler/aarch64/${os_version}/
       ./build

Some configuration items:
./packages-to-install
   If you want to pre-install the software,  you can write the package names in ./packages-to-install.

./files-to-exclude
   If you want remove some unnecessary files, you can write the names in ./files-to-exclude

$HOME/.config/compass-ci/rootfs-passwd
   Set the password for the image into this file.
