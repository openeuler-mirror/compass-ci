# system wide setup

test

## debian packages

	sudo apt-get install docker.io

## openEuler packages

	sudo dnf install docker

# per-user setup

## git repo

	# git clone https://gitee.com/openeuler/compass-ci.git

	cd compass-ci
	echo "export CCI_SRC=$PWD" >> $HOME/.${SHELL##*/}rc
	echo "PATH=$PATH:$PWD/sbin">> $HOME/.${SHELL##*/}rc

## packages

	gem install rest-client
