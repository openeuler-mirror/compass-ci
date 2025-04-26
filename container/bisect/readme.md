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

## 主表结构 (`bisect_tasks`)

| 字段名称             | 类型       | 是否可为空 | 默认值 | 描述                                                                 | 索引建议          |
|----------------------|------------|------------|--------|----------------------------------------------------------------------|-------------------|
| id                   | keyword    | NOT NULL   | -      | 任务唯一标识符（UUIDv4）                                             | 主键(PK)         |
| bad_job_id           | keyword    | NOT NULL   | -      | 需要二分法分析的原始Job ID                                           | 普通索引(IDX_1)  |
| error_id             | keyword    | NOT NULL   | -      | 错误标识符（需配合去重机制）                                         | 唯一索引(UQ_1)  |
| bisect_metrics       | keyword    | NULL       | -      | 性能指标名称（仅性能测试场景使用）                                   | 条件索引(IDX_5)  |
| priority_level       | integer    | NOT NULL   | 1      | 优先级级别：0-低/1-中/2-高                                           | 排序索引(IDX_8)  |
| bisect_status        | keyword    | NOT NULL   | pending| 任务状态枚举：pending/running/paused/success/failed/retrying         | 状态索引(IDX_2)  |
| first_bad_commit     | keyword    | NULL       | -      | 通过bisect定位的首个问题提交                                         | 覆盖索引(IDX_6)  |
| project              | keyword    | NOT NULL   | -      | 所属项目名称（格式：org/repo）                                       | 组合索引(IDX_3)  |
| pkgbuild_repo        | keyword    | NULL       | -      | 软件包构建仓库地址                                                   | -                |
| git_url              | keyword    | NULL       | -      | 上游代码仓库URL                                                      | -                |
| bisect_suite         | keyword    | NOT NULL   | -      | 测试套件标识符（用于跨任务分析）                                     | 组合索引(IDX_3)  |
| first_bad_job_id     | keyword    | NULL       | -      | 问题提交对应的首个失败Job ID                                         | 外键索引(FK_1)   |
| first_result_root    | text       | NULL       | -      | 首次失败结果存储路径（OSS路径格式）                                  | -                |
| work_dir             | text       | NOT NULL   | -      | 任务工作目录（格式：/bisect/yyyy-mm-uuid/）                          | 前缀索引(IDX_4)  |
| start_time           | date       | NULL       | -      | 任务实际开始时间（ISO8601）                                          | 范围索引(IDX_7)  |
| end_time             | date       | NULL       | -      | 任务结束时间（成功/失败时更新）                                      | 范围索引(IDX_7)  |
| commit_history       | text       | NOT NULL   | -      | 提交范围（格式：commit1...commit2）                                  | -                |
| timeout              | integer    | NOT NULL   | 3600   | 超时阈值（秒）                                                       | -                |

## 嵌套表 (`job_commit_mappings`)

| 字段名称        | 类型       | 是否可为空 | 描述                                                                 | 索引建议          |
|-----------------|------------|------------|----------------------------------------------------------------------|-------------------|
| job_id          | keyword    | NOT NULL   | 关联的CI Job标识符                                                   | 联合主键(PK_2)   |
| commit_hash     | keyword    | NOT NULL   | Git提交哈希（完整40位）                                              | 覆盖索引(IDX_9)  |
| metric_value    | text       | NULL       | 性能指标数值（JSON格式存储多维度指标）                               | -                |
| result_root     | keyword    | NOT NULL   | 结果存储路径（OSS路径）                                              | 前缀索引(IDX_10) |
| status          | keyword    | NOT NULL   | 判定状态：bad/good/skip                                              | 位图索引(BIT_1)  |
| timestamp       | date       | NOT NULL   | 任务执行时间戳（精确到毫秒）                                         | 排序索引(IDX_11) |


