# define_files

Meaning:
- We use lkp-tests as client for compass-ci. There are many testcases in lkp-tests. most testcases contain the following files:
	distro/depends/$testcase
	distro/depends/$testcase-dev
	pkg/$testcase/PKGBUILD
	stats/$testcase
	tests/$testcase
	jobs/$testcase.yaml
- When user add new testcase files to lkp-tests or change existing testcase files in lkp-tests, these change files that related with test program would be added to define_files field.
- The define_files field do not need to be specified by user in the $testcase.yaml. It can be generated automatically when user submit with the option '-a'. User can confirm the define_files field in the job.yaml under result_root.

Usage example:
- % submit -a $testcase.yaml testbox=vm-2p8g--$USER os=openeuler os_arch=aarch64 os_version=20.03
- % cat /srv/result/$testcase/vm-2p8g--$USER/$date/$job_id/job.yaml
