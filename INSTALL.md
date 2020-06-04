# system wide setup

## debian packages

	sudo apt-get install docker.io

## openEuler packages

	sudo dnf install docker

# per-user setup

## git repo

	# git clone https://gitee.com/openeuler/crystal-ci.git
	# For now, hosted in crystal server:
	git clone file:///c/crystal-ci.git
	# or clone from your laptop:
	git clone ssh://crystal/c/crystal-ci.git

	cd crystal-ci
	echo "export CCI_SRC=$PWD" >> $HOME/.${SHELL##*/}rc
	echo "PATH=$PATH:$PWD/sbin">> $HOME/.${SHELL##*/}rc

## packages

	gem install rest-client
