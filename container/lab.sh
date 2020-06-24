#!/bin/bash

. $LKP_SRC/lib/yaml.sh

shopt -s nullglob

for i in /etc/crystal-ci/defaults/*.yaml $HOME/.config/crystal-ci/defaults/*.yaml
do
	create_yaml_variables "$i"
done
