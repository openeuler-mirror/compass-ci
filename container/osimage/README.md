# Use the tool to create a new initramfs image.

Usage:

git clone https://gitee.com/openeuler/compass-ci.git
cd compass-ci/rootfs/initramfs/${os_name}/${arch}/${os_version}/
./build

cd compass-ci/container/osimage/
./docker-build-initrd -h

Usage: ./docker-build-initrd.sh --os_name openeuler --os_version 22.03-LTS
Generate initrd of the specified docker_image.

Mandatory arguments to long options are mandatory for short options too.
  -n, --name            the name of generated initramfs
      --arch            the arch of docker_image
      --os_version      the version of openeuler
      --root_passwd     specify the root password of initrd, the default password is "test"
  -h, --help            display this help and exit
  -d, --debug           show the DEBUG level log, default is INFO level.

DEMO:
./docker-build-initrd.sh --os_name openeuler --os_version 22.03-LTS --root_passwd 1234

Some configuration items:
./${os_name}/packages-to-install
   If you want to pre-install the software,  you can write the package names in ./packages-to-install.

./${os_name}/files-to-exclude
   If you want remove some unnecessary files, you can write the names in ./files-to-exclude
