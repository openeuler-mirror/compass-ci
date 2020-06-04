#!/bin/bash
# - hostname

. $LKP_SRC/lib/yaml.sh

: ${hostname:="vm-hi1620-1p1g-1"}

# unicast prefix: x2, x6, xA, xE
export mac=$(echo $hostname | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/0a-\1-\2-\3-\4-\5/')
curl -X PUT "http://localhost:3000/set_host_mac?hostname=${hostname}&mac=${mac}"

(
	if [[ $hostname =~ ^(.*)-[0-9]+$ ]]; then
		tbox_group=${BASH_REMATCH[1]}
	else
		tbox_group=$hostname
	fi

	create_yaml_variables "$LKP_SRC/hosts/${tbox_group}"

	source "$CCI_SRC/providers/$provider/${template}.sh"
)
