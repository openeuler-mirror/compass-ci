scheduler:
	cd src && make

install-depends:
	sbin/install-dependencies.sh
	cd src && shards install

ctags:
	ctags -R --links=no --langmap=ruby:.rb.cr
