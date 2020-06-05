[TOC]

# restful-API
## submit a job
- restAPI: POST "/submit_job"
- request body: {"#!jobs/iperf.yaml":null,"suite":"iperf","testcase":"iperf"...}
- response body: "#{job_id}" (job_id is a global unique sequence number, e.g. 6)
- debug cmd:
	curl -X POST --data '{"testcase": "iperf", "testbox": "myhost", "test-group": "mygroup", "result_root": "/result/ipef"}' http://localhost:3000/submit_job

- inner process:
```sequence
User->Scheduler: POST "/submit_job" job content
Note left of User: job content\nin json format
Scheduler->Redis: <job_id> = get_new_job_id
Redis->Redis: increase sched/seqno2jobid
Scheduler->Scheduler: <job> = JSON.parse(HTML::body)
Scheduler->Scheduler: <tbox_group> = determinQueueName, <tbox_group_queue> = "sched/jobs_to_run/#{tbox_group}"
Scheduler->Redis: add2queue(<tbox_group_queue>, <job_id>)
Redis->Redis: put <job_id> to pending queue <tbox_group_queue> 
Scheduler->ElasticSearch: add("jobs/job", <job>, <job_id>)
ElasticSearch->ElasticSearch: create jobs/job document
Scheduler->User: <job_id>
```
- doing what:
	1. add job_id to pending queue in redis
	2. add a job document in es

- redis storage: 
	Key                   |Value                                        |Type        |
	sched/seqno2jobid     |last_job_id => 64bit number                  |String      |
	<tbox_group_queue>    |[{member => job_id, score => enqueue_time},] |Sorted_Set  |

	Notes:
	enqueue_time: float64
	tbox_group_queue: jobs to run queue (e.g. sched/jobs_to_run/wfg-e595)
	use redis Sorted_Set as a job queue, one per tbox_group.

- es storage:
	add "jobs/job" document (contents of job)
	extend set: job["_id"]=job_id, job["result_root"]=job["result_root"] + "/#{job_id}"

- class members related:
	Scheduler::Enqueue.respon

## qemu-pxe testbox pull a job
- restAPI: GET "/boot.ipxe/mac/:mac" (e.g. "/boot.ipxe/mac/52-54-00-12-34-56")
- request body: none
- response body: "#{ipxe_command}"
- debug cmd:
	curl http://localhost:3000/boot.ipxe/mac/54-52-00-12-24-46

### case 1: <ipxe_command> when find a job
	#!ipxe
	initrd http://<server>:8000/os/debian/aarch64/sid/initrd.lkp
	initrd http://<server>:8800/initrd/lkp/latest/lkp-aarch64.cgz
	initrd http://<scheduler>:3000/job_initrd_tmpfs/<job_id>/job.cgz
	kernel http://<server>:8000/os/debian/aarch64/sid/vmlinuz user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job root=<server>:/os/debian/aarch64/sid rootovl ip=enp0s1:dhcp ro initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz
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
Scheduler->Redis: <job_id> = find_any_job(<tbox_group>)
Redis->Redis: move_job("sched/jobs_to_run/#{tbox_group}", "sched/jobs_running", <job_id>)
Scheduler->ElasticSearch: job = get("job/job", <job_id>)
Scheduler->Scheduler: createJobPackage from job to job.cgz
Scheduler->TestBox: <ipxe_command>
```
- doing what:
	1. use mac to search hostname in es "report/hostnames" document
	2. move job_id from pending queue to "sched/jobs_running" in redis
	3. record {job_id => {"testbox":hostname}} to sched/id2job in redis
	4. create job.cgz, save it to /job_initrd_tmpfs/<job_id>/
	5. create ipxe_command

- redis storage:
	Key          |Value                                        |Type       |
	"sched/jobs_to_run/#{tbox_group}" |[{member => job_id, score => enqueue_time},] |Sorted_Set |
	sched/jobs_running                |[{member => job_id, score => dequeue_time},] |Sorted_Set |
	sched/id2job                      |[{field => job_id, value => help_info},]     |Hash       |

	Notes:
	dequeue_time: float64, times when the job_id put in sched/jobs_running queue
	job_info: record information about a job

- es storage:
	query "report/hostnames" document: index of {mac <=> hostname}

- class members related:
	Scheduler::Utils.findJobBoot

## job download
- restAPI: GET "/job_initrd_tmpfs/:job_id/job.cgz" (e.g. "/job_initrd_tmpfs/6/job.cgz")
- request body: none
- response body:
	#less job.cgz
	lkp
	lkp/scheduled
	lkp/scheduled/job.yaml
	lkp/scheduled/job.sh
- debug cmd: no need

- inner process:
```sequence
TestBox->Scheduler: GET "/job_initrd_tmpfs/<job_id>/job.cgz"
Note right of Scheduler: send fsdir_root/<job_id>/job.cgz\nto testbox
Scheduler->TestBox: send_file job.cgz
```
- doing what:
	1. send job.cgz to client
	2. remove job.cgz

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
Scheduler->ElasticSearch: update_job_parameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->Redis: update_job_parameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->TestBox: Done
```
- doing what:
	1. update "jobs/job" document in es

- redis storage: no change
- es storage:
	update "jobs/job" document
	extend set: job[parameter]=value

- class members
	Scheduler::Monitor.update_job_parameter

## report job finished
- restAPI: GET "/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=<job_id>"
- request body: none
- response body: "Done"
- debug cmd:
        curl "/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"

- inner process:
```sequence
User->Scheduler: GET "/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=<job_id>"
Scheduler->Redis: remove_running(job_id)
Scheduler->User: Done
```
- doing what:
        1. move job from redis queue "sched/jobs_running" to "sched/extract_stats" 
        2. remove job from redis queue "sched/id2job"

- redis storage: 
        move_job("sched/jobs_running", "queue/extract_stats", job_id):move job from redis queue "sched/jobs_running" to "sched/extract_stats"
        hdel("sched/id2job", job_id):remove job from redis queue "sched/id2job"
- es storage: no change

## report mac's hostname
- restAPI: PUT "/set_host_mac?hostname=:hostname&mac=:mac" (e.g. "/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56")
- request body: none
- response body: "Done"
- debug cmd:
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
- debug cmd:
	curl http://localhost:9200/jobs/job/6        # query a job with job_id=6
	curl http://localhost:9200/jobs/job/_search  # query all jobs

# redis client debug cmd
## list all keys: keys *
## get String key value: get sched/seqno2jobid
## get Sorted-Set key value: zrange sched/jobs_running 0 -1 | zrange sched/jobs_running 0 -1 withscores | zrange sched/jobs_to_run/mygroup 0 -1
## get all Hash keys field: hkeys sched/id2job
## get a Hash key value: hget sched/id2job 6  #->6 is a job_id


---
# API use scenario
## scenario 1: developer debug use
1. use [PUT "/set_host_mac?hostname=:hostname&mac=:mac"] to register a {mac => hostname}
	debug shell md: curl -X PUT "http://localhost:3000/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56"
2. use [POST "/submit_job"] to submit a job
	debug shell cmd: /0_addjob.sh iperf.yaml # at cci/user-client/helper
3. runs qemu.sh at cci/providers to get a job and run it
	qemu.sh will call [GET "/boot.ipxe/mac/:mac"] to get ipxe boot paramater
	qemu.sh will call [GET "/job_initrd_tmpfs/<job_id>/job.cgz"] go get the job package
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

### prepare public directory for program use (?? 777)
	mkdir public
	chmod 777 public

### run
	./scheduler

## 3. how to build docker image <like sch-ruby-a:v0.00d>
### copy program
	cp ./scheduler ../container/scheduler/

### go to container
	cd ../container/scheduer

### build it
	./build

```
