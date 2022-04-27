# id(=job_id)
## meaning
format: $lab.$seqno
A unique sequence number in a lab.
When user submit a job, scheduler save a job document in ES DB.

## who use it
Used the specify the value of id when you use es-find/es-jobs to check out a job.

## example
```
es-find id=$job_id
es-jobs id=$job_id
```
