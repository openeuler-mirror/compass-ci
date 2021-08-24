# id
  The **id** is a global unique sequence number.

  When user submit a job, scheduler add job_id to ready queue in redis,
  and save a job document in ES DB.

# How to use id?
  es-find id=$job_id
  es-jobs id=$job_id
  ...


