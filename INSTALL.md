# system wide setup

## debian packages

	sudo apt-get install docker.io

## openEuler packages

	sudo dnf install docker

# per-user setup

## git repo

	# git clone https://gitee.com/wu_fengguang/crystal-ci.git

	cd crystal-ci
	echo "export CCI_SRC=$PWD" >> $HOME/.${SHELL##*/}rc
	echo "PATH=$PATH:$PWD/sbin">> $HOME/.${SHELL##*/}rc

## packages

	gem install rest-client
