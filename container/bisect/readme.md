## bisect submit

### way1:
	run in special testbox

ensure security:
- account/token
- visit services


common testbox:
	submit upload lkp-tests tar ball, run in testbox

secure testbox:
	submit NO UPLOAD lkp-tests tar ball
	run only selected list of programs
	run in a dedicated host machine, FW can visit services


### way2:
submit job1
	submit job2, reuse same account info
problem: consumes his credit / machine time

### way3:
compass ci container/ run as service
refer to delimiter service
	system bisect account

	provide API/new-bisect-task
		add to ES
	
	loop:
		consume one task from ES
		fork process, start bisect
			bisect step
			submit job
			change bisect-task state=finish

submit-jobs

### regression db
### bisect task queue
### bisect tasks management and dashboard

	bisect task name	
	suite	start_time/run_time  step group_id

# Bisect 任务数据库设计文档

## 主表结构 (`bisect`)
CCI_SRC/sbin/manti-table-bisect.sql


## 回归检查表 (`regression`)
CCI_SRC/sbin/manti-table-regression.sql




