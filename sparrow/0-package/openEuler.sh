#!/bin/bash

pkgs=(
	vim
	git
	ruby
	rubygems
	qemu
	lvm2
	docker-engine
)

yum install -y "${pkgs[@]}"
