#!/bin/bash
[[ $CCI_LAB ]] || CCI_LAB=sparrow
[[ $LKP_SRC ]] || LKP_SRC=/c/lkp-tests

. $LKP_SRC/lib/yaml.sh
create_yaml_variables "$LKP_SRC/labs/${CCI_LAB}.yaml"
