#!/bin/bash

pkgs=(
	vim
	git
	gcc
	make
	ruby
	rubygems
	ruby-devel
	bridge-utils
	qemu
	lvm2
	docker-engine
)

yum install -y "${pkgs[@]}"
