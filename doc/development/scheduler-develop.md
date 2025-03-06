How to setup minimal develop environment for developing the Compass CI scheduler.

## install code depends

### install `lkp-tests`

```
git clone https://gitee.com/compass-ci/lkp-tests
cd lkp-tests
make install
# re-run bash or zsh, so that new LKP_SRC etc. env vars take effect
```

It'll install depends and setup environment variables in your .bashrc or .zshrc

### install `compass-ci`

```
git clone https://gitee.com/openeuler/compass-ci
cd compass-ci
make install
```

## install os/kernel depends

If running as root (suitable for production run), output will be saved to /srv/
If running as normal user (suitable for local development), output will be saved to $HOME/.cache/compass-ci/

Below I assume local development deployment as normal user.

### common busybox binaries

The lkp-tests framework scripts have to run in any OS the job.yaml specifies, not all OS pre-install the external commands lkp-tests need.
So the solution is to prepare a static busybox, which will be mounted into all
container testboxes or passed as initrd into VM/HW testboxes for use by lkp-tests framework.

```
sbin/fetch-busybox-wrapper.sh

# check output
ls ~/.cache/compass-ci/file-store/busybox/
aarch64  amd64  arm64  armhf  i386  mips64el  ppc64el  riscv64  s390x  x86_64
```

### Run test jobs in container

In development, it's convenient to run scheduler/providers as normal user.
In this case, you'll need install podman, so as to run containers in rootless mode.

If run docker by normal user, there will be security risks and permission
issues when exchanging result/cache data between host/guest OS.

If run by root, either podman or docker is fine.

```
apt-get install podman      # if you want running container in normal user
apt-get install docker.io   # if you want running container in root user
```

The OS docker images will be auto pulled.

### Run test jobs in QEMU

You'll need create kernel and os images first. You only need prepare the kernel/os that you want the test jobs to run in.

Way1: copy from server
```
mkdir ~/.cache/compass-ci
cd ~/.cache/compass-ci
# you may want refine this command to more concrete dirs/images
rsync -a crystal:/srv/file-store .
```

Way2: build by yourself

```
# vi and edit OS_LIST first to fit your needs
sbin/fetch-kernel-packages.sh

# check outputs
ls ~/.cache/compass-ci/file-store/boot2os/*
/home/wfg/.cache/compass-ci/file-store/boot2os/aarch64:
debian@12  openeuler@22.03  openeuler@24.03  openeuler@24.09  opensuse@15.6  ubuntu@24.04

/home/wfg/.cache/compass-ci/file-store/boot2os/loongson:
debian@12

/home/wfg/.cache/compass-ci/file-store/boot2os/riscv64:
debian@12  openeuler@24.03  openeuler@24.09  ubuntu@24.04

/home/wfg/.cache/compass-ci/file-store/boot2os/x86_64:
debian@12  openeuler@20.03  openeuler@22.03  openeuler@24.03  openeuler@24.09  opensuse@15.6  ubuntu@24.04
```

```
# vi and edit OS_LIST first to fit your needs
sbin/docker2osimage

# check outputs
ls ~/.cache/compass-ci/file-store/docker2os/*
/home/wfg/.cache/compass-ci/file-store/docker2os/aarch64:
alpine@3.21.cgz  debian@12.cgz  openeuler@20.03.cgz  openeuler@24.03.cgz  rockylinux@9.cgz
centos@9.cgz     fedora@42.cgz  openeuler@22.03.cgz  openeuler@24.09.cgz  ubuntu@24.04.cgz

/home/wfg/.cache/compass-ci/file-store/docker2os/x86_64:
alpine@3.21.cgz       centos@9.cgz   fedora@40.cgz  openeuler@20.03.cgz  openeuler@24.03.cgz  opensuse@15.6.cgz  ubuntu@24.04.cgz
archlinux@latest.cgz  debian@12.cgz  fedora@42.cgz  openeuler@22.03.cgz  openeuler@24.09.cgz  rockylinux@9.cgz
```

## core development cycle in 3 terminals

### build/run scheduler

```
cd src
make cscope
make
../sbin/scheduler-debug

# if you want customize scheduler config
cp ../container/scheduler/scheduler-config.yaml .
vi scheduler-config.yaml
# then re-run scheduler
```

### run providers in another terminal

```
export ENABLE_PACKAGE_CACHE=1 # may speed up package installation inside testbox, useful for repeatedly debug run development cycles
export DEBUG=1 # will run qemu in graphics mode
cd providers
./multi-qemu-docker
```

### submit jobs in another terminal

```
cd $LKP_SRC
submit host-info.yaml
submit -m boot.yaml program.sleep.runtime=3600      # watch job log and login
submit host-info.yaml osv=debian@12 testbox=dc-8g   # customize job with key=val
```

## debug tips

```
# view dispatch data structure
curl http://localhost:3000/scheduler/v1/debug/dispatch

# view job content for job_id 25030215415267500
curl http://localhost:3000/scheduler/v1/jobs/25030215415267500

# view hosts/jobs in dashboard
$LKP_SRC/sbin/dashboard --viewer=firefox
```
