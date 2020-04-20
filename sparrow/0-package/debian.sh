#!/bin/bash

pkgs=(
	lvm2
	docker.io
)

apt-get install "${pkgs[@]}"
