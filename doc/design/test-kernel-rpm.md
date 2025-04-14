# test rpm kernels

## rpm packages available

Assume we want to test some kernel under this url

<https://eulermaker.compass-ci.openeuler.openatom.cn/api/ems5/repositories/kernel6_6:openEuler-22.03-LTS-SP4:everything/openEuler%3A22.03-LTS-SP4/aarch64/history/f0f721d4-23df-11ef-96e5-3e91e18f8c69/steps/kernel6_6%3AopenEuler-22.03-LTS-SP4%3Aeverything-openEuler%3A22.03-LTS-SP4-aarch64-4/Packages/>


```
bpftool-6.6.0-27.0.0.32.oe2203sp4.aarch64.rpm      06-Jun-2024 17:09              865613
bpftool-6.6.0-27.0.0.rt30.4.oe2203sp4.aarch64.rpm  06-Jun-2024 17:09              295633
bpftool-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm      06-Jun-2024 17:14              880085
bpftool-debuginfo-6.6.0-27.0.0.32.oe2203sp4.aar..> 06-Jun-2024 17:09             1084913
bpftool-debuginfo-6.6.0-27.0.0.rt30.4.oe2203sp4..> 06-Jun-2024 17:09              515053
bpftool-debuginfo-6.6.0-28.0.0.34.oe2203sp4.aar..> 06-Jun-2024 17:14             1099577
haoc-kernel-6.6.0-27.0.0.32.oe2203sp4.aarch64.rpm  06-Jun-2024 17:09            61822877
haoc-kernel-6.6.0-27.0.0.32.oe2203sp4.src.rpm      06-Jun-2024 17:10           228623731
haoc-kernel-debugsource-6.6.0-27.0.0.32.oe2203s..> 06-Jun-2024 17:09            57342321
haoc-kernel-devel-6.6.0-27.0.0.32.oe2203sp4.aar..> 06-Jun-2024 17:09            15973529
haoc-kernel-headers-6.6.0-27.0.0.32.oe2203sp4.a..> 06-Jun-2024 17:09             2145029
haoc-kernel-source-6.6.0-27.0.0.32.oe2203sp4.aa..> 06-Jun-2024 17:09           185967145
haoc-kernel-tools-6.6.0-27.0.0.32.oe2203sp4.aar..> 06-Jun-2024 17:09              848309
haoc-kernel-tools-devel-6.6.0-27.0.0.32.oe2203s..> 06-Jun-2024 17:09              575421
kernel-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm       06-Jun-2024 17:14            61864897
kernel-6.6.0-28.0.0.34.oe2203sp4.src.rpm           06-Jun-2024 17:14           228662897
kernel-debuginfo-6.6.0-27.0.0.32.oe2203sp4.aarc..> 06-Jun-2024 17:09           509807897
kernel-debuginfo-6.6.0-28.0.0.34.oe2203sp4.aarc..> 06-Jun-2024 17:14           509677385
kernel-debugsource-6.6.0-28.0.0.34.oe2203sp4.aa..> 06-Jun-2024 17:14            57313009
kernel-devel-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm 06-Jun-2024 17:14            15975133
kernel-headers-6.6.0-28.0.0.34.oe2203sp4.aarch6..> 06-Jun-2024 17:14             2159561
kernel-rt-6.6.0-27.0.0.rt30.4.oe2203sp4.aarch64..> 06-Jun-2024 17:09            61703521
kernel-rt-6.6.0-27.0.0.rt30.4.oe2203sp4.src.rpm    06-Jun-2024 17:10           228020405
kernel-rt-debuginfo-6.6.0-27.0.0.rt30.4.oe2203s..> 06-Jun-2024 17:09           485210145
kernel-rt-debugsource-6.6.0-27.0.0.rt30.4.oe220..> 06-Jun-2024 17:09            56383353
kernel-rt-devel-6.6.0-27.0.0.rt30.4.oe2203sp4.a..> 06-Jun-2024 17:09            15357729
kernel-rt-headers-6.6.0-27.0.0.rt30.4.oe2203sp4..> 06-Jun-2024 17:09             1575105
kernel-rt-source-6.6.0-27.0.0.rt30.4.oe2203sp4...> 06-Jun-2024 17:10           185404057
kernel-rt-tools-6.6.0-27.0.0.rt30.4.oe2203sp4.a..> 06-Jun-2024 17:09              278421
kernel-rt-tools-debuginfo-6.6.0-27.0.0.rt30.4.o..> 06-Jun-2024 17:09              155077
kernel-rt-tools-devel-6.6.0-27.0.0.rt30.4.oe220..> 06-Jun-2024 17:09                5517
kernel-source-6.6.0-28.0.0.34.oe2203sp4.aarch64..> 06-Jun-2024 17:14           185938625
kernel-tools-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm 06-Jun-2024 17:14              862725
kernel-tools-debuginfo-6.6.0-27.0.0.32.oe2203sp..> 06-Jun-2024 17:09              724933
kernel-tools-debuginfo-6.6.0-28.0.0.34.oe2203sp..> 06-Jun-2024 17:14              739349
kernel-tools-devel-6.6.0-28.0.0.34.oe2203sp4.aa..> 06-Jun-2024 17:14              589857
perf-6.6.0-27.0.0.32.oe2203sp4.aarch64.rpm         06-Jun-2024 17:09             2276333
perf-6.6.0-27.0.0.rt30.4.oe2203sp4.aarch64.rpm     06-Jun-2024 17:09             1706453
perf-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm         06-Jun-2024 17:14             2290829
perf-debuginfo-6.6.0-27.0.0.32.oe2203sp4.aarch6..> 06-Jun-2024 17:09             5380013
perf-debuginfo-6.6.0-27.0.0.rt30.4.oe2203sp4.aa..> 06-Jun-2024 17:09             4810393
perf-debuginfo-6.6.0-28.0.0.34.oe2203sp4.aarch6..> 06-Jun-2024 17:14             5394457
python3-perf-6.6.0-27.0.0.32.oe2203sp4.aarch64.rpm 06-Jun-2024 17:09              675637
python3-perf-6.6.0-27.0.0.rt30.4.oe2203sp4.aarc..> 06-Jun-2024 17:09              105773
python3-perf-6.6.0-28.0.0.34.oe2203sp4.aarch64.rpm 06-Jun-2024 17:14              690109
python3-perf-debuginfo-6.6.0-27.0.0.32.oe2203sp..> 06-Jun-2024 17:09              937561
python3-perf-debuginfo-6.6.0-27.0.0.rt30.4.oe22..> 06-Jun-2024 17:09              367865
python3-perf-debuginfo-6.6.0-28.0.0.34.oe2203sp..> 06-Jun-2024 17:14              952081
raspberrypi-kernel-6.6.0-26.0.0.4.oe2203sp4.aar..> 06-Jun-2024 16:50            28719161
raspberrypi-kernel-6.6.0-26.0.0.4.oe2203sp4.src..> 06-Jun-2024 16:50           229257764
raspberrypi-kernel-devel-6.6.0-26.0.0.4.oe2203s..> 06-Jun-2024 16:50            15122985
raspberrypi-kernel-rt-6.6.0-26.0.0.rt.1.oe2203s..> 06-Jun-2024 16:50            28583205
raspberrypi-kernel-rt-6.6.0-26.0.0.rt.1.oe2203s..> 06-Jun-2024 16:50           229427782
raspberrypi-kernel-rt-devel-6.6.0-26.0.0.rt.1.o..> 06-Jun-2024 16:50            15106253
```

## job fields and data flow

1) user: prepare job fields

```yaml
kernel_version: 6.6.0-27.0.0.32.oe2203sp4.aarch64
# one or more kernel/module/driver rpms
kernel_rpms: {{yum.repo}}/Packages/haoc-kernel-{{kernel_version}}.rpm
yum.repo: https://eulermaker.compass-ci.openeuler.openatom.cn/api/ems5/repositories/kernel6_6:openEuler-22.03-LTS-SP4:everything/openEuler%3A22.03-LTS-SP4/aarch64/history/f0f721d4-23df-11ef-96e5-3e91e18f8c69/steps/kernel6_6%3AopenEuler-22.03-LTS-SP4%3Aeverything-openEuler%3A22.03-LTS-SP4-aarch64-4
yum.install: perf
```

2) submit client: will expand/replace the above ``{{some.job_field}}`` job variable references

3) scheduler TODO:
```sh
  create $kernel_cache_dir
  for rpm in $kernel_rpms:
	  rpm2cpio $rpm to $kernel_cache_dir/$rpm-$hash/cpio/$cpio
	  if $cpio has /boot:
        unpack $cpio to $kernel_cache_dir/$rpm-$hash/
		set job.kernel_uri to http ... $kernel_cache_dir/$rpm-$hash/boot/vmlinuz-... # refactor current code
	  if $cpio has /lib/modules:
		job.modules_uri += $kernel_cache_dir/$rpm-$hash/cpio/$cpio

  [done] convert job.modules_uri type to array
```

4) lkp-tests setup/yum: create /etc/yum.repos.d/ config file and install user land packages
