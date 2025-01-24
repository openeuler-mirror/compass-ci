ctags:
	ctags -R --links=no --langmap=ruby:.rb.cr

install-depends:
	sudo apt-get install crystal shards
	cd src && shards install
scheduler:
	crystal build -o sbin/scheduler src/scheduler.cr
lifecycle:
	crystal build -o sbin/lifecycle src/lifecycle.cr
watch-jobs:
	crystal build -o sbin/watch-jobs src/watch-jobs.cr
monitoring:
	crystal build -o sbin/monitoring src/monitoring.cr
extract-stats:
	crystal build -o sbin/extract-stats src/extract-stats.cr
delimiter:
	crystal build -o sbin/delimiter src/delimiter.cr
updaterepo:
	crystal build -o sbin/updaterepo src/updaterepo.cr
serial-logging:
	crystal build -o sbin/serial-logging src/serial-logging.cr
post-extract:
	crystal build -o sbin/post-extract src/post-extract.cr
