---
# client dependence

## system env
yum install ruby-devel

gem install cucumber
gem install rest-client

## how to use
ruby ./client/src/lkp.rb queue ./iperf.yaml


---
# helper shell command

## empty hostname regist
curl -X DELETE http://localhost:9200/report
## run qemu will "get no job" : because of no host regist

## regist a hostname
curl -X PUT "http://localhost:3000/report?hostname=wfg-e595&mac=52-54-00-12-34-56"

## add job
0_addjob.sh iperf.yaml

## run qemu
2_runqemu.sh
## rerun qemu got "no job now" : because the only job has been done

## other
1_showjob.sh job_id  # show job_id's content in es
3_dispcgz.sh job_id  # list job_id's file
