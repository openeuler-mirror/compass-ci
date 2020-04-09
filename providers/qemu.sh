#!/bin/bash
# - hostname

. $LKP_SRC/lib/yaml.sh

: ${hostname:="vm-pxe-hi1620-1p1g"}

(
	create_yaml_variables "$LKP_SRC/hosts/$hostname"

	source "$CCI_SRC/providers/$provider/${template}.sh"
)
