# 多机测试中，用after-milestone表达脚本间等待关系

## after-milestone的添加方式: 全自动 or 全手动

像if-role那样的缺省值+额外标注方式，不适用于after-milestone，容易引起混乱。

一个job要么不手工标注任意after-milestone属性，由框架自动标注(下面情况1);
要么全部交由用户标注(下面情况2)。

1. 通常情况，框架透明使能，用户**无需加任何配置项**

适用于只有server/client roles的情况。Example job yaml:

```yaml
daemon:
    d1:
    d2:
program:
    p1:
    p2:
```

默认行为：the first program p1 will wait for the last daemon d2
自动标注：program.p1.after-milestone: d2

2. 任意复杂情况，用户通过加after-milestone, **显式标注所有依赖**

## after-milestone 全手动标注情况

    daemon.xxx:
    program.yyy.after-milestone: xxx

milestone的名字可以是两种

1. daemon/program script name

这种情况，框架会自动在对应script执行后，追加script name到job.milestone字段

2. 在某个daemon/program script内部，显式调用的`report_milestone $milestone_name`

这种功能看起来足够灵活，但目前来看暂无必要实现。

## milestone wait scheme

job yaml
```
    daemon:
        d1:
        d2:
    program:
        p1:
            after-milestone: d2
        p2:
```

job2sh
```
    # if role server
    run_job()
    {
        run_daemon d1
        run_daemon d2
        report_milestone 'd2'
        wait_jobs jobid1.job_stage='finished' jobid2.job_stage='finished'
    }

    # if role client
    run_job()
    {
        report_job_stage 'wait_peer'
        wait_jobs jobid1.milestone='d2' jobid2.job_stage='wait_peer'
        report_job_stage 'run-program'
        run_program p1
        run_program p2
    }
```

## references

```
/c/compass-ci/doc/test-guide/multi-device-test.md
/c/compass-ci/doc/job/fields/job_stage.md
/c/compass-ci/src/scheduler/request_cluster_state.cr
/c/lkp-tests/cluster/cs-vm-2p16g
/c/lkp-tests/lib/job.sh
/c/lkp-tests/jobs/ceph.yaml
/c/lkp-tests/programs/mugen/jobs/network-test.yaml
/c/lkp-tests/programs/mugen/run
```
