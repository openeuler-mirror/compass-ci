#!/bin/bash

pkgs=(
	vim
	git
	gcc
	gcc-c++
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
