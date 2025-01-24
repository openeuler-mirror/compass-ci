ctags:
	ctags -R --links=no --langmap=ruby:.rb.cr

install-depends:
	sudo apt-get install crystal shards
	cd src && shards install
