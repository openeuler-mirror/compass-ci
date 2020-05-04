# ssh

## setup in your local laptop

	cat >> ~/.ssh/config <<-EOF
	Host crystal
	  Hostname 124.90.34.227
	  Port 22113
	EOF

	# password-less login
	[ -f ~/.ssh/id_rsa.pub ] || ssh-keygen
	ssh-copy-id crystal

## setup in crystal server

	cat >> ~/.ssh/config <<-EOF
	Host alpine
	  Hostname localhost
	  Port 2200
	  User team

	Host debian
	  Hostname localhost
	  Port 2201
	  User team
	EOF

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
