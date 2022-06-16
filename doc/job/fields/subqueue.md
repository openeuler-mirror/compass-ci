# meaning
First, you should study **queue** field from queue.md.

use submitter's my_email as the default value.common users don't need to pay attention to this field.

so every user has a subqueue, combined "queue/subqueue" can indicate which user owns it.

for the future, subqueue may be used for user's task priority consumption.


# where set it
compass-ci/src/lib/job.cr
```
private def set_subqueue
    self["subqueue"] = self["my_email"] unless self["subqueue"] == "idle"
```

# where use it
put/get job id to etcd for read/wait/in_process queue
```
sched/ready/#{job.queue}/#{job.subqueue}/#{job.id}
sched/wait/#{job.queue}/#{job.subqueue}/#{job.id}
sched/in_process/#{job.queue}/#{job.subqueue}/#{job.id}
```
