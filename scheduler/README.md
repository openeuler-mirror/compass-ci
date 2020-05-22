[TOC]

# restful-API
## submit a job
- restAPI: POST "/submit_job"
- request body: {"#!jobs/iperf.yaml":null,"suite":"iperf","testcase":"iperf"...}
- response body: "#{job_id}" (job_id is a global unique sequence number, e.g. 6)
- debug curl cmd:
	curl -X POST --data '{"testcase": "iperf", "testbox": "myhost", "test-group": "mygroup", "root_result": "/result"}' http://localhost:3000/submit_job

- inner process:
```sequence
User->Scheduler: POST "/submit_job" job content
Note left of User: job content\nin json format
Scheduler->Redis: <job_id> = get_new_job_id
Redis->Redis: increase global_job_id
Scheduler->Scheduler: <job> = JSON.parse(HTML::body)
Scheduler->Scheduler: <tbox_group> = determinQueueName
Scheduler->Redis: add2queue(<tbox_group>, <job_id>)
Redis->Redis: put <job_id> to pending queue <tbox_group> 
Scheduler->ElasticSearch: add("jobs/job", <job>, <job_id>)
ElasticSearch->ElasticSearch: create jobs/job document
Scheduler->User: <job_id>
```
- doing what:
	1. add job_id to pending queue in redis
	2. add a job document in es

- redis storage: 
	Key             |Value                                        |Type        |
	global_job_id   |last_job_id                                  |String      |
	<tbox_group>    |[{member => job_id, score => enqueue_time},] |Sorted_Set  |

	Notes:
	last_job_id, job_id: int64
	enqueue_time: float64, times when the job_id is put to pending queue (testgroup_:tbox_group. e.g. testgroup_wfg-e595)
	use redis Sorted_Set as a queue.

- es storage:
	add "jobs/job" document (contents of job)
	extend set: job["id"]=job_id, job["root_result"]=job["root_result"]/job_id

- class members related:
	Scheduler::Enqueue.respon

## qemu-pxe testbox pull a job
- restAPI: GET "/boot.ipxe/mac/:mac" (e.g. "/boot.ipxe/mac/52-54-00-12-34-56")
- request body: none
- response body: "#{ipxe_command}"
- debug curl cmd:
	curl http://localhost:3000/boot.ipxe/mac/54-52-00-12-24-46

### case 1: <ipxe_command> when find a job
	#!ipxe
	initrd http://<server>:8000/os/debian/initrd.lkp
	initrd http://<server>:8800/initrd/lkp/latest/lkp-aarch64.cgz
	initrd http://<scheduler>:3000/tmpfs/<job_id>/job.cgz
	kernel http://<server>:8000/os/debian/vmlinuz user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job root=<server>:/os/debian rootovl ip=enp0s1:dhcp ro initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz
	boot

#### who generate this output
	#
	#	>>>>>>>>>> waiting for patch:
	#	>> NOTE >>    who generate initrd.lkp lkp-aarch64.cgz job.cgz vmlinuz
	#	<<<<<<<<<<    and etc.
	#

### case 2: <ipxe_command> when find no job
	#!ipxe
	echo ...
	No job now
	echo ...
	reboot

- inner process:
```sequence
TestBox->Scheduler: GET "/boot.ipxe/mac/52-54-00-12-34-56"
Scheduler->ElasticSearch: <hostname> = get_config("report/hostnames", "52-54-00-12-34-56")
Scheduler->Scheduler: <tbox_group> = getTestgroupName(<hostname>)
Scheduler->Redis: <job_id> = findAnyJob(<tbox_group>)
Redis->Redis: moveJob(<tbox_group>, "running", <job_id>)
Scheduler->ElasticSearch: job = get("job/job", <job_id>)
Scheduler->Scheduler: createJobPackage from job to job.cgz
Scheduler->TestBox: <ipxe_command>
```
- doing what:
	1. use mac to search hostname in es "report/hostnames" document
	2. move job_id from pending queue to "running" in redis
	3. record {job_id => {"testbox":hostname}} to hi_running in redis
	4. create job.cgz in scheduler
	5. create ipxe_command

- redis storage:
	Key          |Value                                        |Type       |
	<tbox_group> |[{member => job_id, score => enqueue_time},] |Sorted_Set |
	running      |[{member => job_id, score => dequeue_time},] |Sorted_Set |
	hi_running   |[{field => job_id, value => help_info},]     |Hash       |

	Notes:
	dequeue_time: float64, times when the job_id put in running queue
	help_info: record information about a running job

- es storage:
	query "report/hostnames" document: index of {mac <=> hostname}

- class members related:
	Scheduler::Utils.findJobBoot

## job download
- restAPI: GET "/tmpfs/:job_id/job.cgz" (e.g. "/tmpfs/6/job.cgz")
- request body: none
- response body:
	#less job.cgz
	lkp
	lkp/scheduled
	lkp/scheduled/job.yaml
	lkp/scheduled/job.sh
- debug curl cmd: no need

- inner process:
```sequence
TestBox->Scheduler: GET "/tmpfs/<job_id>/job.cgz"
Note right of Scheduler: send fsdir_root/<job_id>/job.cgz\nto testbox
Scheduler->TestBox: send_file job.cgz
```
- doing what:
	1. send job.cgz to client
	2. remove job.cgz in scheduler

- redis storage: no change
- es storage: no change

## report job var
- restAPI: GET "/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=:job_id&[:parameter=:value]"
           e.g. "/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=6&start_time=1587725398
	   [:parameter=:value] -> [] means it is optional
- request body: none
- response body: "Done"

- inner process:
```sequence
TestBox->Scheduler: GET "/~lkp/cgi-bin/lkp-jobfile-append-var?\njob_file=/lkp/scheduled/job.yaml&job_id=<job_id>&[<parameter> => <value>]"
Scheduler->ElasticSearch: updateJobParameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->Redis: updateJobParameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->TestBox: Done
```
- doing what:
	1. update "jobs/job" document in es

- redis storage: no change
- es storage:
	update "jobs/job" document
	extend set: job[parameter]=value

- class members
	Scheduler::Monitor.updateJobParameter

## report mac's hostname
- restAPI: PUT "/set_host_mac?hostname=:hostname&mac=:mac" (e.g. "/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56")
- request body: none
- response body: "Done"
- debug curl cmd:
	curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56"

- inner process:
```sequence
User->Scheduler: PUT "/set_host_mac?hostname=<hostname>&\nmac=<mac>"
Scheduler->ElasticSearch: add_config("report/hostnames",\n<mac> => <hostname>)
Scheduler->User: Done
```
- doing what:
	1. create/update "report/hostnames" document in es

- redis storage: no change
- es storage:
	create/update "report/hostnames" document: index of {mac <=> hostname}


---
# es storage
## job saved in "jobs/job" documents
- debug curl cmd:
	curl http://localhost:9200/jobs/job/6        # query a job with job_id=6
	curl http://localhost:9200/jobs/job/_search  # query all jobs

# redis client debug cmd
## list all keys: keys *
## get String key value: get global_job_id
## get Sorted-Set key value: zrange running 0 -1 | zrange running 0 -1 withscores | zrange testgroup_mygroup 0 -1
## get all Hash keys field: hkeys hi_running
## get a Hash key value: hget hi_running 6  #->6 is a job_id


---
# API use scenario
## scenario 1: developer debug use
1. use [PUT "/set_host_mac?hostname=:hostname&mac=:mac"] to register a {mac => hostname}
	debug shell md: curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56"
2. use [POST "/submit_job"] to submit a job
	debug shell cmd: /0_addjob.sh iperf.yaml # at cci/user-client/helper
3. runs qemu.sh at cci/providers to get a job and run it
	qemu.sh will call [GET "/boot.ipxe/mac/:mac"] to get ipxe boot paramater
	qemu.sh will call [GET "/tmpfs/<job_id>/job.cgz"] go get the job package
	qemu.sh start a testbox, and the testbox will call [GET "/~lkp/cgi-bin/..."]


---
# develper help

## 1. how to build exe file <scheduler>

### install shards, redis -> 2.5.3 (@crystal 0.33)
	./0_shards.sh

###  fix ElasticSearch error
lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr
L79 response = HTTP::Client.post(url: endpoint, body: post_data) ->
 response = HTTP::Client.post(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
L82 response = HTTP::Client.put(url: endpoint, body: post_data) ->
 response = HTTP::Client.put(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})

### build it
	./build.sh

## 2. how to debug <scheduler>
### stop running scheduler server
	docker stop s001-alpine

### prepare scheduler.yaml, change localhost to docker0's ip (like 172.17.0.1)
	ifconfig docker0

### cp (?? share operate)
	copy /c/lkp-tests/sbin/create-job-cpio.sh .
	chmod 777 ./create-job-cpio.sh

### prepare public directory for program use (?? 777)
	mkdir public
	chmod 777 public

### run
	./scheduler

## 3. how to build docker image <like sch-ruby-a:v0.00d>
### copy program
	cp ./scheduler ../container/scheduler/
	cp ./create-job-cpio.sh ../container/scheduler/
	cp ./scheduler.yaml ../container/scheduler/

### go to container
	cd ../container/scheduer

### build it
	./build

```
