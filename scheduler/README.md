[TOC]

# restful-API
## submit a job
- restAPI: POST "/queues"
```sequence
User->Scheduler: POST "/queues" job content
Note left of User: job content\nin json format
Scheduler->Redis: <job_id> = getSN
Redis->Redis: increase global_job_id
Scheduler->Scheduler: <job> = JSON.parse(HTML::body)
Scheduler->Scheduler: <tbox_group> = determinQueueName
Scheduler->Redis: add2queue(<tbox_group>, <job_id>)
Redis->Redis: put <job_id> to pending queue <tbox_group> 
Scheduler->ElasticSearch: add("jobs/job", <job>, <job_id>)
ElasticSearch->ElasticSearch: create jobs/job document
Scheduler->User: <job_id>
Note right of Scheduler: job_id is a number
```

## qemu-pxe testbox pull a job
- restAPI: GET "/boot.ipxe/mac/[:mac]"
```sequence
TestBox->Scheduler: GET "/boot.ipxe/mac/52-54-00-12-34-56"
Scheduler->ElasticSearch: <hostname> = get_config("report/hostnames", "52-54-00-12-34-56")
Scheduler->Scheduler: <tbox_group> = getTestgroupName(<hostname>)
Scheduler->Redis: <job_id> = findAnyJob(<tbox_group>)
Redis->Redis: moveJob(<tbox_group>, "running", <job_id>)
Scheduler->ElasticSearch: job = get("job/job", <job_id>)
Scheduler->Scheduler: createJobPackage from job to job.cgz
Scheduler->TestBox: ipxe command
Note right of Scheduler: ipxe command
```

### ipxe command: find a job
```
#!ipxe
initrd http://<server>:8000/os/debian/initrd.lkp
initrd http://<server>:8800/initrd/lkp/latest/lkp-aarch64.cgz
initrd http://<scheduler>:3000/tmpfs/<job_id>/job.cgz
kernel http://<server>:8000/os/debian/vmlinuz user=lkp job=/lkp/scheduled/job.yaml RESULT_ROOT=/result/job root=<server>:/os/debian rootovl ip=enp0s1:dhcp ro initrd=initrd.lkp initrd=lkp-aarch64.cgz initrd=job.cgz
boot
```

### ipxe command: find no job
```
#!ipxe
echo ...
No job now
echo ...
reboot
```

## job download
- restAPI: GET "/tmpfs/[:job_id]/job.cgz"
```sequence
TestBox->Scheduler: GET "/tmpfs/<job_id>/job.cgz"
Note right of Scheduler: send fsdir_root/<job_id>/job.cgz\nto testbox
Scheduler->TestBox: send_file job.cgz
```

## report job var
- restAPI: GET "/~lkp/cgi-bin/lkp-jobfile-append-var?job_file=/lkp/scheduled/job.yaml&job_id=[:job_id]&[:parameter=:value]"
```sequence
TestBox->Scheduler: GET "/~lkp/cgi-bin/lkp-jobfile-append-var?\njob_file=/lkp/scheduled/job.yaml&job_id=<job_id>&<parameter>=<value>"
Scheduler->ElasticSearch: updateJobParameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->Redis: updateJobParameter("job"=><job_id>,\n<parameter> => <value>)
Scheduler->TestBox: Done
```

## report mac's hostname
- restAPI: PUT "/report?hostname=[:hostname]&mac=[:mac]"
```sequence
User->Scheduler: PUT "/report?hostname=<hostname>&\nmac=<52-54-00-12-34-56>"
Scheduler->ElasticSearch: get_config("report/hostnames",\n<52-54-00-12-34-56> => <hostname>)
Scheduler->User: Done
```


---
# develper help

## 1. how to build exe file <scheduler>

### install shards, redis -> 2.5.3 (@crystal 0.33)
```Bash
./0_shards.sh
```

###  fix ElasticSearch error
lib/elasticsearch-crystal/src/elasticsearch/api/namespace/common.cr
L79 response = HTTP::Client.post(url: endpoint, body: post_data) ->
 response = HTTP::Client.post(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})
L82 response = HTTP::Client.put(url: endpoint, body: post_data) ->
 response = HTTP::Client.put(url: endpoint, body: post_data, headers: HTTP::Headers{"Content-Type" => "application/json"})

### build it
```Bash
./build.sh
```

## 2. how to debug <scheduler>
### stop running scheduler server
```Bash
docker stop s001-alpine
```

### prepare scheduler.yaml, change localhost to docker0's ip (like 172.17.0.1)
```Bash
ifconfig docker0
```

### cp (?? share operate)
```Bash
copy /c/lkp-tests/sbin/create-job-cpio.sh .
chmod 777 ./create-job-cpio.sh
```

### prepare public directory for program use (?? 777)
```Bash
mkdir public
chmod 777 public
```

### run
```Bash
./scheduler
```

## 3. how to build docker image <like sch-ruby-a:v0.00d>
### copy program
```Bash
cp ./scheduler ../container/scheduler/
cp ./create-job-cpio.sh ../container/scheduler/
cp ./scheduler.yaml ../container/scheduler/
```

### go to container
```Bash
cd ../container/scheduer
```

### build it
```Bash
./build
```
