#!/bin/bash

bash ../../scheduler/build.sh
cp ../../scheduler/scheduler .
cp /c/lkp-tests/sbin/create-job-cpio.sh .

docker build -t sch-ruby-a:v0.00d .

rm -f scheduler
rm -f ../../scheduler/scheduler
rm -f create-job-cpio.sh
