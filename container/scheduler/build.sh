#!/bin/bash

bash ../../scheduler/build.sh
cp ../../scheduler/scheduler .

docker build -t sch-ruby-a:v0.00d .

rm -f scheduler
rm -f ../../scheduler/scheduler
