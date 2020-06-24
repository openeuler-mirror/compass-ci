#!/bin/bash -e

cd /c/cci/user-client/helper

run_job()
{
	./0_addjob.sh ../jobs/$1
	./2_runqemu.sh
}

export hostname=vm-pxe-hi1620-2p8g-1
run_job iperf-pxe.yaml

export hostname=vm-hi1620-2p8g-1
run_job iperf-vm.yaml







