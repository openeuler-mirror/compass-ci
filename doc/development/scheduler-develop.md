# Compass CI Scheduler Development Setup Guide

A minimal setup guide for developing the Compass CI scheduler.
*Tested on Debian/Ubuntu systems. Adjust package manager commands for other distributions.*

## Table of Contents
1. [Install Dependencies](#install-dependencies)
2. [Environment Configuration](#environment-configuration)
3. [Container/QEMU Setup](#containerqemu-setup)
4. [Development Workflow](#development-workflow)
5. [Debugging & Monitoring](#debugging--monitoring)

---

## Install Dependencies

### 1. Container/QEMU/Tools Dependencies

If run docker in normal user, there will be security risks and permission
issues when exchanging result/cache data between host/guest OS.

```bash
# For rootless containers (recommended for development):
sudo apt-get install podman

# For root containers:
sudo apt-get install docker.io

# QEMU dependencies
sudo apt-get install qemu-system qemu-utils

# Utilities
sudo apt-get install -y jq make cscope git rsync curl wget
```

### 2. Clone & Install Core Components

```bash
# 1. Install lkp-tests
git clone https://gitee.com/compass-ci/lkp-tests
cd lkp-tests
make install
# pick up new env vars LKP_SRC, PATH etc.
source ~/.bashrc  # or source ~/.zshrc for zsh users

# 2. Install compass-ci
git clone https://gitee.com/openeuler/compass-ci
cd compass-ci
make install
```

---

## Environment Configuration

### Path Location
- **Root user**: Outputs go to `/srv/`
- **Normal user**: Outputs go to `$HOME/.cache/compass-ci/`

*All examples below assume normal user development*

### Busybox Setup

The lkp-tests framework scripts have to run in any OS the job.yaml specifies,
not all OS pre-install the external commands lkp-tests need.

The solution is to prepare a static busybox, which will be mounted into all
container testboxes or passed as initrd into VM/HW testboxes for use by
lkp-tests framework.

```bash
# From compass-ci directory
./sbin/fetch-busybox-wrapper.sh

# Verify:
ls ~/.cache/compass-ci/file-store/busybox/
# Should see multiple architecture directories like these
aarch64  riscv64  x86_64
```

---

## Container/QEMU Setup

### 1. Container Images
Docker/Podman images will auto-download on first use. To pre-cache:

```bash
podman pull docker.io/library/debian:12
```

### 2. QEMU Images (Choose One Method)

QEMU runs need kernel, modules and OS cpio images.

#### Method A: Copy from Server
```bash
mkdir -p ~/.cache/compass-ci
# Refine the path to only copy the kernel/OS that you want test jobs to run in
rsync -av crystal:/srv/file-store ~/.cache/compass-ci/
```

#### Method B: Build Locally
```bash
# Edit OS_LIST first to select desired OS versions
vim sbin/kernel-boot2os.sh
vim sbin/docker2osimage

# Build kernel packages
./sbin/fetch-kernel-packages.sh

# Build OS images
./sbin/docker2osimage

# Check Output
ls ~/.cache/compass-ci/file-store/boot2os/*
ls ~/.cache/compass-ci/file-store/docker2os/*
```

---

## Development Workflow

Use three terminal sessions:

### Terminal 1: Scheduler
```bash
cd compass-ci

# Customize config
mkdir -p ~/.config/compass-ci/scheduler/
cp container/scheduler/config.yaml ~/.config/compass-ci/scheduler/config.yaml
vim ~/.config/compass-ci/scheduler/config.yaml  # Make adjustments

cd src
make && ../sbin/scheduler-debug
```

### Terminal 2: Providers
```bash
export DEBUG=1                 # Show QEMU GUI
cd compass-ci/providers
./multi-qemu-docker
```

### Terminal 3: Job Submission
```bash
# Submit sample jobs
submit host-info.yaml
submit -m boot.yaml program.sleep.runtime=3600      # -m to watch job log and login
submit host-info.yaml osv=debian@12 testbox=dc-8g   # customize job with key=val
```

---

## Debugging & Monitoring

### Scheduler Inspection
```bash
# View dispatch queue
curl http://localhost:3000/scheduler/v1/debug/dispatch

# Get job details
curl http://localhost:3000/scheduler/v1/jobs/$job_id | jq .
```

### Web Dashboard
```bash
$LKP_SRC/sbin/dashboard --viewer=firefox
```

### Login to Testbox
```bash
$LKP_SRC/sbin/console --logs --events --console $job_id
```

### Log Locations
```bash
cd ~/.cache/compass-ci

ls provider/hosts/dc-1/ # check current job's downloaded files, extracted cpio files, test results
172.17.0.1:3000  lkp  result_root

less provider/logs/dc-1 # check current job's console log
```
