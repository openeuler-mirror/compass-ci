[TOC]

---
# restful-API
First of all, you should deploy the lkp-tests and compass-ci project
And set the environment variables needed for running (modify "/etc/profile.d/compass.sh")
```  
LKP_SRC: ~/code/lkp-tests    # path to your lkp-tests repo
CCI_SRC: ~/code/compass-ci   # path to your compass-ci repo
SCHED_HOST: 172.17.0.1       # hostname or ip of the scheduler
SCHED_PORT: 3000             # port of the scheduler
```    
* '${variable}' is used at shell command, means the value of variable
* '#{variable}' is used at crystal language, means the value of variable
* '\<variable>' is just let this variable can be show stronger
* '[variable]' means this variable is optional

## submit a job
- restAPI: POST "/scheduler/v1/jobs/submit"
- request body: {"#!jobs/iperf.yaml":null, "suite":"iperf", ...}
- response body: "#{job_id}" (job_id is a global unique sequence number, e.g. 6)
- debug cmd:
  curl -X POST --data '{"suite": "iperf", "testbox": "myhost", "test-group": "mygroup", "result_root": "/result/ipef"}' http://${SCHED_HOST}:${SCHED_PORT}/scheduler/v1/jobs/submit

- v0.1.x inner process:
```sequence
User->Scheduler: POST "/scheduler/v1/jobs/submit" with job content
Note left of User: job content\nin json format
Scheduler->Sched: sched.\nsubmit_job(env)
Sched->Redis: <job_id> = get_new_job_id
Redis->Redis: increase string key\n"sched/seqno2jobid"
Sched->Sched: <job> = Job.new(JSON.parse(HTML::body)\n+ "id":#{job_id})
Sched->Sched: <tbox_group> = job.tbox_group,\n<tbox_group_queue> =\n"sched/jobs_to_run/#{tbox_group}"
Sched->Redis: add2queue(tbox_group_queue, job_id)
Redis->Redis: push <job_id> to ready queue\n(redis key) <tbox_group_queue>
Sched->ElasticSearch: set_job_content(job)
ElasticSearch->ElasticSearch: create <JOB_INDEX_TYPE>\ndocument about job
Sched->Scheduler: <job_id>
Scheduler->User: <job_id>
```
-- doing what:
   1. add job_id to ready queue in redis
   2. add a job document in es

-- redis storage:
Key|Value|Type
:-|:-|:-
sched/seqno2jobid  |last_job_id => 64bit number                  |String
<tbox_group_queue> |[{member => job_id, score => enqueue_time},] |Sorted_Set

 Notes:
   enqueue_time: float64
   tbox_group_queue: jobs to run queue (e.g. "sched/jobs_to_run/wfg-e595")
   use redis Sorted_Set as a job queue, one per tbox_group.

- v0.2.x inner process:
```sequence
User->Scheduler: POST "/scheduler/v1/jobs/submit" with job content
Note left of User: job content\nin json format
Scheduler->Sched: sched.submit_job(env)
Sched->Sched: job_content = JSON.parse(http.body)
Sched->JobHelper: <task_queue_name> = get_tbox_group
Sched->TaskQueue: add_task(task_queue_name,\ntask_description)
TaskQueue->Sched: <task_id>
Sched->Sched: <job> = job_content\n+ "id":#{task_id as job_id}
Sched->ElasticSearch: set_job_content(job)
ElasticSearch->ElasticSearch: create <JOB_INDEX_TYPE>\ndocument about job
Sched->Scheduler: <job_id>
Scheduler->User: <job_id>
```
-- doing what:
   1. use TaskQueue.add_task to add a task (for current job)
   2. add a job document in es

-- redis storage: no change

- es storage:
  add JOB_INDEX_TYPE document (contents of job)

- class members related:
  Sched.submit_job(env)
  ElasticSearch::Client.set_job_content(job)
  Job.new, Job.tbox_group

## qemu-pxe testbox consume a job
- restAPI: GET "/boot.ipxe/mac/:mac" (e.g. "/boot.ipxe/mac/52-54-00-12-34-56")
- request body: none
- response body: "#{ipxe_command}"
- debug cmd:
  curl http://${SCHED_HOST}:${SCHED_PORT}/boot.ipxe/mac/54-52-00-12-24-46

### case 1: <ipxe_command> when find a job
	#!ipxe
	initrd http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/initrd.lkp
	initrd http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_use}/lkp-#{job.os_arch}.cgz
	initrd http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz
	kernel http://#{OS_HTTP_HOST}:#{OS_HTTP_PORT}/os/#{job.os_dir}/vmlinuz user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job root=#{job.kernel_append_root} rootovl ip=dhcp ro initrd=initrd.lkp initrd=lkp-#{job.os_arch}.cgz initrd=job.cgz
	boot

#### who generate this output
  - initrd.lkp: container dracut-initrd generate this for special os. basic lkp-tests system.
  - vmlinuz: container dracut-initrd generate this for special os. os kernel.
  - lkp-#{job.os_arch}.cgz: container init-lkp generate this for current user. customized installation of external programs and/or system packages.
  - job.cgz: service scheduler generate this. the content is job.yaml, job.sh about the job.

### case 2: <ipxe_command> when find no job
	#!ipxe
	echo ...
	No job now
	echo ...
	reboot

- v0.1.x inner process:
```sequence
TestBox->Scheduler: GET "/boot.ipxe/mac/52-54-00-12-34-56"
Scheduler->Sched: <ipxe_command> = Sched.\nfind_job_boot("52-54-00-12-34-56")
Sched->Redis: <hostname> = redis.hget("sched/mac2host",\n"52-54-00-12-34-56")
Sched->Sched: <tbox_group> = JobHelper.get_tbox_group(hostname)
Sched->Redis: <job_id> = find_job(tbox_group)
Redis->Redis: move_job("sched/jobs_to_run/#{tbox_group}",\n"sched/jobs_running",\njob_id)
Sched->ElasticSearch: job = get_job(job_id)
Sched->Redis: set_job(job)
Sched->Sched: Jobfile::Operate.create_job_cpio\ngenerate job.cgz from job
Sched->Scheduler: <ipxe_command>
Scheduler->TestBox: <ipxe_command>
```
-- doing what:
   1. use mac to search hostname in redis key "sched/mac2host"
   2. translate hostname to tbox_group
   3. move job_id from redis key "sched/#{tbox_group}" to redis key "sched/jobs_running"
   4. get_job from es (with job_id)
   5. record {job_id => job} to redis key "sched/id2job"
   6. create job.cgz, save it to /job_initrd_tmpfs/#{job_id}/
   7. generate ipxe_command and return it to caller

-- redis storage:
Key|Value|Type
:-|:-|:-
sched/jobs_to_run/#{tbox_group} |[{member => job_id, score => enqueue_time},] |Sorted_Set
sched/jobs_running              |[{member => job_id, score => dequeue_time},] |Sorted_Set
sched/id2job                    |[{field => job_id, value => job_info},]      |Hash

  Notes:
    dequeue_time: float64, times when the job_id put in redis key "sched/jobs_running"
    job_info: record information about a job

- v0.2.x inner process:
```sequence
TestBox->Scheduler: GET "/boot.ipxe/mac/52-54-00-12-34-56"
Scheduler->Sched: <ipxe_command> = Sched.\nfind_job_boot("52-54-00-12-34-56")
Sched->Redis: <hostname> = redis.hget("sched/mac2host",\n"52-54-00-12-34-56")
Sched->Sched: <tbox_group> = JobHelper.get_tbox_group(hostname)
Sched->TaskQueue: consume_task("sched/#{tbox_group}")
TaskQueue->Sched: {"id":task_id} | nil
Sched->ElasticSearch: job = get_job(task_id as job_id)
Sched->Sched: Jobfile::Operate.create_job_cpio\ngenerate job.cgz from job
Sched->Scheduler: <ipxe_command>
Scheduler->TestBox: <ipxe_command>
```
-- doing what:
   1. use mac to search hostname in redis key "sched/mac2host"
   2. translate hostname to tbox_group
   3. call consume_task with tbox_group to get available task_id
   4. get_job from es (with the task_id as job_id)
   5. record {job_id => job} to redis key "sched/id2job"
   6. create job.cgz, save it to /job_initrd_tmpfs/#{job_id}/
   7. generate ipxe_command and return it to caller

-- redis storage:
Key|Value|Type
:-|:-|:-
sched/id2job                    |[{field => job_id, value => job_info},]      |Hash

- es storage:
  query JOB_INDEX_TYPE document (contents of job)

- class members related:
  Sched.find_job_boot
  Elasticsearch::Client.get_job
  Jobfile::Operate.create_job_cpio

## docker container testbox consume a job
- restAPI: GET "/boot.container/host/:host" (e.g. "/boot.container/host/dc-1g-1")
- request body: none
- response body:
  "{
    "docker_images": "centos:7",
    "lkp": "http://#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT}/initrd/lkp/#{job.lkp_initrd_use}/lkp-#{job.os_arch}.cgz",
    "job": "http://#{SCHED_HOST}:#{SCHED_PORT}/job_initrd_tmpfs/#{job.id}/job.cgz"
  }" |
  "{}"
- debug cmd:
  curl http://${SCHED_HOST}:${SCHED_PORT}/boot.container/host/dc-1g-1

- inner process:
-- doing what:
   most same to <qemu-pxe testbox consume a job>, but
   1. direct gives hostname (testbox), no need search from the mac address
   2. only 3 parameter, use <"docker_images"> to start a container, and
      mount the <"lkp"> initrd to run the user submited <"job">

## physical[|qemu-grub] testbox consume a job
- restAPI: GET "/boot.grub/mac/:mac" (e.g. "/boot.grub/mac/52:54:00:12:34:56")
- request body: none
- response body: "#{grub_command}"
- debug cmd:
  curl http://${SCHED_HOST}:${SCHED_PORT}/boot.grub/mac/52:54:00:12:34:56

### case 1: <grub_command> when find a job
	#!grub
	linux (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})/os/#{job.os_dir}/vmlinuz user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job rootovl ip=dhcp ro root=#{job.kernel_append_root}
	initrd (http,#{OS_HTTP_HOST}:#{OS_HTTP_PORT})/os/#{job.os_dir}/initrd.lkp (http,#{INITRD_HTTP_HOST}:#{INITRD_HTTP_PORT})/initrd/lkp/#{job.lkp_initrd_user}/#{initrd_lkp_cgz} (http,#{SCHED_HOST}:#{SCHED_PORT})/job_initrd_tmpfs/#{job.id}/job.cgz"
	boot

### case 2: <grub_command> when find no job
	#!grub
	echo ...
	No job now
	echo ...
	reboot

- inner process:
-- doing what:
   same to <qemu-pxe testbox consume a job>

## job download
- restAPI: GET "/job_initrd_tmpfs/:job_id/job.cgz" (e.g. "/job_initrd_tmpfs/6/job.cgz")
- request body: none
- response body:
  #less job.cgz
  lkp
  lkp/scheduled
  lkp/scheduled/job.yaml
  lkp/scheduled/job.sh
- debug cmd:
  no need

- inner process:
```sequence
TestBox->Scheduler: GET "/job_initrd_tmpfs/<job_id>/job.cgz"
Scheduler->Scheduler: <fsdir_root> = Kemal.config.public_folder
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
- request body: none
- response body: "Done"

- inner process:
```sequence
TestBox->Scheduler: GET "/~lkp/cgi-bin/lkp-jobfile-append-var?\njob_file=/lkp/scheduled/job.yaml\n&job_id=<job_id>&[<parameter> => <value>]"
Scheduler->Sched: sched.updatea_job_parameter(env)
Sched->Sched: job_content = {"id" => #{job_id},\n"<parameter>" => "<value>"}
Sched->Redis: update_job(job_content)
Scheduler->TestBox: Done
```
- doing what:
  1. update "sched/id2job" content in redis

- redis storage: update "sched/id2job" content
- es storage: no change

- class members
  Sched.update_job_prarameter(env)
  Redis::Client.updatea_job(job_content)

## report job finished
- restAPI: GET "/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=<job_id>"
- request body: none
- response body: "Done"
- debug cmd:
  curl "http://${SCHED_HOST}:${SCHED_PORT}\n/~lkp/cgi-bin/lkp-post-run?job_file=/lkp/scheduled/job.yaml&job_id=40"

- v0.1.x inner process:
```sequence
User->Scheduler: GET "/~lkp/cgi-bin/lkp-post-run\n?job_file=/lkp/scheduled/job.yaml&job_id=<job_id>"
Scheduler->Sched: close_job(job_id)
Sched->Redis: <job> = get_job(job_id)
Sched->ElasticSearch: set_job_content(job)
Sched->Redis: move_job("sched/jobs_running",\n"extract_stats", job_id)
Sched->Redis: remove_finished_job(job_id)
Scheduler->User: Done
```
-- doing what:
   1. update JOB_INDEX_TYPE document (contents of job)
   2. move job from redis queue "sched/jobs_running" to "queue/extract_stats"
   3. remove job from redis queue "sched/id2job"

-- redis storage:
   move_job job_id from redis key "sched/jobs_running" to "queue/extract_stats"
   del key job_id from "sched/id2job"

- v0.2.x inner process:
```sequence
User->Scheduler: GET "/~lkp/cgi-bin/lkp-post-run\n?job_file=/lkp/scheduled/job.yaml&job_id=<job_id>"
Scheduler->Sched: close_job(job_id)
Sched->Redis: <job> = get_job(job_id)
Sched->ElasticSearch: set_job_content(job)
Sched->TaskQueue: hand_over_task("sched/#{jobs.tbox_group}",\n"extract_stats", job_id)
Sched->Redis: remove_finished_job(job_id)
Scheduler->User: Done
```
-- doing what:
   1. update JOB_INDEX_TYPE document (contents of job)
   2. call hand_over_task with parameter "sched/#{job.tbox_group}", "extract_stats", job_id
   3. remove job from redis queue "sched/id2job"

-- redis storage:
   del key job_id from "sched/id2job"

- es storage: update job documents

## report mac's hostname
- restAPI: PUT "/set_host_mac?hostname=:hostname&mac=:mac" (e.g. "/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56")
- request body: none
- response body: "Done"
- debug cmd:
  curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56"

- inner process:
```sequence
User->Scheduler: PUT "/set_host_mac?hostname=\n<hostname>&mac=<mac>"
Scheduler->Sched: set_host_mac(mac, hostname)
Sched->Redis: hash_set("sched/mac2host",\nmac, hostname)
Scheduler->User: Done
```
- doing what:
  1. create/update redis hash key "sched/mac2host"

- redis storage: no change
Key|Value|Type
:-|:-|:-
sched/mac2host                  |[{field => mac, value => hostname,]          |Hash
- es storage: no change


---
# es storage
- job saved in JOB_INDEX_TYPE documents
- debug cmd:
  curl http://localhost:9200/${JOB_INDEX_TYPE}/6        # query a job with job_id=6
  curl http://localhost:9200/${JOB_INDEX_TYPE}/_search  # query all jobs


---
# redis client debug cmd
- list all keys: keys sched*
- get String key value: get sched/seqno2jobid
- get Sorted-Set key value: zrange sched/jobs_running 0 -1 | zrange sched/jobs_running 0 -1 withscores | zrange sched/jobs_to_run/mygroup 0 -1
- get all Hash keys field: hkeys sched/id2job
- get a Hash key value: hget sched/id2job 6  #->6 is a job_id

---
# API use scenario
## scenario 1: developer debug, submit a job and consume with quem.sh
1. use [PUT "/set_host_mac?hostname=:hostname&mac=:mac"] to register a {mac => hostname}
  debug shell md: curl -X PUT "http://${SCHED_HOST}:${SCHED_PORT}/set_host_mac?hostname=wfg-e595&mac=52-54-00-12-34-56"
2. use [POST "/scheduler/v1/jobs/submit"] to submit a job
  debug shell cmd: ./0_addjob.sh iperf.yaml # at cci/user-client/helper
  or lkp cmd: submit-job iperf.yaml
3. runs qemu.sh at cci/providers to get a job and run it
  qemu.sh will call [GET "/boot.ipxe/mac/:mac"] to get ipxe boot paramater
  qemu.sh will call [GET "/job_initrd_tmpfs/<job_id>/job.cgz"] go get the job package
  qemu.sh start a testbox, and the testbox will call [GET "/~lkp/cgi-bin/..."]


---
# develper help

## 1. how to build exe file <scheduler>
at compass-ci host, scheduler will be run as a docker container.
   use the script at $CCI_SRC/container/scheduler/build to build the container image
   use the script at $CCI_SRC/container/scheduler/run to start the container.

if you want manually build scheduler in crystal language environment, you need:
  1) run shards: to install essential require package (see $CCI_SRC/src/shards.yml)
  2) fix current elasticSearch err:
	lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr
	L79 response = HTTP::Client.post(url: endpoint, body: post_data) -> response = HTTP::Client.post(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
	L82 response = HTTP::Client.put(url: endpoint, body: post_data) -> response = HTTP::Client.put(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
  3) run crystal build scheduler.cr -o m_scheduler

we have construct docker images <alpine:crystal-shards> and <alpine:scheduler-dev> for scheduler container to use.
you can simply call the scheduler's build and run script.


# How to start your own scheduler container

## 1.Add port configuration, select an unused port number like <3001>, write in xxx.yaml like "example.yaml"
     cat > ~/.config/compass-ci/defaults/example.yaml <<EOF
     SCHED_PORT: 3001
     EOF

## 2.Build docker image
     cd $CCI_SRC/container/scheduler
     ./build

## 3.Start container
     cd $CCI_SRC/container/scheduler
     ./run

# How to submit and execute tasks

## 1.Modify iperf.yaml's field, You can find it in the "~/compass-ci/user-client/helper" directory
     vim $CCI_SRC/user-client/helper/iperf.yaml
     runtime: 30                    # unit in seconds, the time can be shortened
     arch: aarch64
     testbox: vm-2p8g--$USER  # echo $USER for your own user name

## 2.Submit job
     submit-job $_CCI_SRC/user-client/helper/iperf.yaml

## 3.Execute QEMU script
     cd $CCI_SRC/providers
     ./my-qemu.sh

# How to view scheduler (docker container) log
  docker logs -f s001-alpine-3001
  docker logs --tail==100 s001-alpine-3001    # Show the last 100 lines of logs
