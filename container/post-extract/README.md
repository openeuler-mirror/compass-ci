# post-extract

## purpose

- Some post-processing is required after the job is executed.
- After the PR build is complete, an email will be sent to notify the build result.


## process

- After extract-stats, put the job to "/queues/post-extract/#{job_id}" queue of etcd
- post-extract service get all tasks, filter out PR build job and send email to notify build result. 

'''
	extract-stats service
	      |
	      |  put the job to "/queues/post-extract/#{job_id}" queue of etcd
	      V		
	 post-extract
	      |
	      |  get tasks from etcd
	      v
	  MailWork
	      |
	      |  find PR build jobs
	      V
	  send email
'''
