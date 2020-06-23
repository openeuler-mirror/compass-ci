#!/bin/bash -e

job_dir=$1
scheduled_dir=$job_dir/lkp/scheduled

job_sh=$job_dir/job.sh
job_yaml=$job_dir/job.yaml

mkdir -p $scheduled_dir
cp $job_yaml $scheduled_dir

chmod +x $job_sh
cp $job_sh $scheduled_dir

cd $job_dir
find lkp | cpio --quiet -o -H newc | gzip > job.cgz

rm -fr ./lkp
