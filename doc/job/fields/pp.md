# pp
## meaning
program params

## example
job.yaml
'''
nr_threads: 200%
iterations: 100x
task:
  task2:
    ebizzy:
      duration: 10s
      iterations: 2
    fwq:
  fsmark:
    nr_threads: 100%
'''

submit script will parse them as below and add to job.yaml
'''
pp:
  ebizzy:
    nr_threads: 200%
    duration: 10s
    iterations: 2
  fwq:
    iterations: 100x
  fsmark:
    nr_threads: 100%
    iterations: 100x
'''

## condition
this field add by submit script, common users don't need to pay attention to this field.

## reference
$LKP_SRC/lib/job.rb
function name add_pp
