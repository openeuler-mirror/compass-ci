#!/bin/bash

pkgs=(
	vim
	lvm2
	docker.io
	ruby-full
	qemu
)

apt-get install -y "${pkgs[@]}"
