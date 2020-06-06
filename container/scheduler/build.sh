#!/bin/bash

bash ../../scheduler/build.sh
mv ../../scheduler/scheduler .

docker build -t sch-ruby-a:v0.00d .

rm scheduler
