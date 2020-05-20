[TOC]

# restful-API
## submit a job
- restAPI: POST "/submit_job"
- request body: {"#!jobs/iperf.yaml":null,"suite":"iperf","testcase":"iperf"...}
- response body: "#{job_id}" (job_id is a global unique sequence number, e.g. 6)

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

## qemu-pxe testbox pull a job
- restAPI: GET "/boot.ipxe/mac/:mac" (e.g. "/boot.ipxe/mac/52-54-00-12-34-56")
- request body: none
- response body: "#{ipxe_command}"

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

## job download
- restAPI: GET "/tmpfs/:job_id/job.cgz" (e.g. "/tmpfs/6/job.cgz")
- request body: none
- response body:
	#less job.cgz
	lkp
	lkp/scheduled
	lkp/scheduled/job.yaml
	lkp/scheduled/job.sh

- inner process:
```sequence
TestBox->Scheduler: GET "/tmpfs/<job_id>/job.cgz"
Note right of Scheduler: send fsdir_root/<job_id>/job.cgz\nto testbox
Scheduler->TestBox: send_file job.cgz
```

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

## report mac's hostname
- restAPI: PUT "/set_host_mac?hostname=:hostname&mac=:mac" (e.g. "/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56")
- request body: none
- response body: "Done"

- inner process:
```sequence
User->Scheduler: PUT "/set_host_mac?hostname=<hostname>&\nmac=<mac>"
Scheduler->ElasticSearch: get_config("report/hostnames",\n<mac> => <hostname>)
Scheduler->User: Done
```

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
