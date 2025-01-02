# lkp client submit flow

## env var
caoxl@crystal ~% which submit
/home/caoxl/c2c/lkp-tests/sbin/submit

caoxl@crystal ~% env|grep SRC
CCI_SRC=/home/caoxl/c2c/compass-ci
LKP_SRC=/home/caoxl/c2c/lkp-tests

caoxl@crystal ~% echo $PATH
/home/caoxl/c2c/lkp-tests/sbin:/home/caoxl/c2c/lkp-tests/bin:/home/caoxl/c2c/compass-ci/sbin:...

caoxl@crystal ~% ls $LKP_SRC/sbin
adapt-packages           ccb     compare             dump-stat             install-dependencies.sh  lkp-renew           mmplot     os-benchmarks-release.sh  port-meta.rb  show-depends-packages  unzip-vmlinuz
add-distro-packages.sh   ccb.rb  create-job-cpio.sh  extract-result-stats  install-run-jobs.sh      make.cross          monitor    pack                      return        split-job              update-printk-error-messages
add-PKGBUILD-depends.rb  cci     create-meta.rb      fixup-meta.rb         job2sh                   makepkg             mplot      pack-deps                 run           submit                 validate-matrix-in-docker.sh
batch-submit             cci.rb  doc                 hardware-gmail.sh     job2sh.cr                makepkg-deps        my-submit  pacman-LKP                search        unite-params
cancel                   cli     do-local-pack       hosts                 jobs                     make-test-count.py  ncompare   pkgmap                    select        unite-stats

caoxl@crystal ~% ls $LKP_SRC/bin
create-stats-matrix  expand-job       job-mrt    lkp               log_test             perf-events  proc-local       run-ipconfig  run-local-monitor.sh  set_nic_irq_affinity  yaml-to-shell-vars
dump-yaml            gen-doc          job-path   lkp-setup-rootfs  merge_config.sh      port-tests   program-options  run-lkp       run-local.sh          setup-local
event                install-run-job  kexec-lkp  log_cmd           merge-remote-result  post-run     rsync-rootfs     run-local     run-with-job          wait.sh

## submit host-info.yaml
$LKP_SRC/sbin/submit host-info.yaml
=>
handle cmd params and find job.yaml from

"#{Dir.pwd}/#{jobfile}"
"#{LKP_SRC}/jobs/**/#{jobfile}"
"#{LKP_SRC}/programs/*/jobs/#{jobfile}"
=>
split job and init job_json

add_pp
add_os_fields
add_install_depend_packages
add_define_files
add_timeout
use_manual_install_cmdline
=>
pack $LKP_SRC and add pkg_data to job_json
this function upload your lkp-tests and use your lkp-tests in testbox

add_pkg_data
=>
begin_submit and call scheduler submit_job api

scheduler_client.submit_job(job_json)
=>
if there is no upload file in scheduler server, then init upload_fields and add it to job_json

PackUploadFields.new(job).pack(upload_fields)
begin_submit and call scheduler submit_job api
