#!/bin/bash -e

run_job()
{
	export hostname=$2
	./0_addjob.sh ../jobs/$1
	./2_runqemu.sh
}

cd /c/cci/user-client/helper

dmidecode -s system-product-name | grep -iq "virtual" && exit
run_job iperf-pxe.yaml	vm-pxe-hi1620-2p8g-1
run_job iperf-vm.yaml	vm-hi1620-2p8g-1
