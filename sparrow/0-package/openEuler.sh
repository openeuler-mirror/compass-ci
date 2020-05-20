#!/bin/bash

pkgs=(
	lvm2
	docker-engine
)

yum install "${pkgs[@]}"
