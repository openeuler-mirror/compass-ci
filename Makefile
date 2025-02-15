scheduler:
	crystal build -o sbin/scheduler src/scheduler.cr
ctags:
	ctags -R --links=no --langmap=ruby:.rb.cr

install-depends:
	sudo apt-get install crystal shards
	cd src && shards install
delimiter:
	crystal build -o sbin/delimiter src/delimiter.cr
updaterepo:
	crystal build -o sbin/updaterepo src/updaterepo.cr
post-extract:
	crystal build -o sbin/post-extract src/post-extract.cr
