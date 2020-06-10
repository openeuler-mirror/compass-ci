#!/bin/bash

pkgs=(
	vim
	lvm2
	gcc
	g++
	make
	docker.io
	ruby-full
	ruby-dev
	bridge-utils
	qemu
)

apt-get install -y "${pkgs[@]}"
