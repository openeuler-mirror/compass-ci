#!/bin/bash
# - hostname

. $LKP_SRC/lib/yaml.sh

: ${hostname:="vm-pxe-hi1620-1p1g-1"}


export mac=$(echo $hostname | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1-\2-\3-\4-\5-\6/')
curl -X PUT http://localhost:3000/set_host_mac?hostname=${hostname}&mac=${mac} 

(
	create_yaml_variables "$LKP_SRC/hosts/${hostname%-*}"

	source "$CCI_SRC/providers/$provider/${template}.sh"
)
