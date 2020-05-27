#!/bin/bash

pkgs=(
	vim
	git
	ruby
	rubygems
	ruby-devel
	bridge-utils
	qemu
	lvm2
	docker-engine
)

yum install -y "${pkgs[@]}"
