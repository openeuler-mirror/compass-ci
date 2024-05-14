# git

## user setting

	git config --global user.name "Your Name"
	git config --global user.email "youremail@yourdomain.com"

Example:

	git config --global user.name "Wu Fengguang"
	git config --global user.email "wfg@mail.ustc.edu.cn"

## repos

Clone the following git repos to your $HOME

	git clone file:///c/todo.git
	git clone https://gitee.com/compass-ci/lkp-tests.git
	git clone https://gitee.com/openeuler/compass-ci.git

Then read through documents

	lkp-tests/doc/INSTALL.md
	compass-ci/doc/INSTALL.md
	compass-ci/doc/development/code-spec.md
	compass-ci/doc/development/learning-resources.md

# crystal compiler

## local install

Follow instructions here:

	https://crystal-lang.org/install/

## arm build environment in docker

We created an alpine docker for running crystal compiler.
It's the only convenient way to use crystal in aarch64.
Usage:
	ssh crystal      # first login to our Kunpeng server
	ssh team@alpine  # then login to the docker

We also provided a global wrapper script "crystal" for use
in our Kunpeng server.

## development tips

Ruby => Crystal code conversion
https://github.com/DocSpring/ruby_crystal_codemod

Interactive console like Ruby's irb/pry
https://github.com/crystal-community/icr

# vim setup

	git clone https://github.com/rhysd/vim-crystal
	cd vim-crystal
	cp -R autoload ftdetect ftplugin indent plugin syntax ~/.vim/

# vscode setup

Install these extensions:

- Markdown Preview Enhanced
  document at https://shd101wyy.github.io/markdown-preview-enhanced/

- Crystal Language

	Need standalone install crystal compiler (mentioned above) and
	crystal language server (below) first.

	git clone https://github.com/crystal-lang-tools/scry.git
	# then follow instructions of the "Installation" section in scry/README.md

- Ruby

- Ruby Solargraph


# email notification app

Usage:

        ssh -X crystal
        cd; wmmaiload &

Look and feel:

        http://tnemeth.free.fr/projets/dockapps.html

The docker app will flash when there are new/unread emails.
