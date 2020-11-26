# category

Meaning:
- Each test has its category, the category field is a test type of test cases.
- When you write a job yaml, you can choose one of benchmark, functional, noise-benchmark
  to assign the value of category.
- Here are some differences about different category values:
  1. If category is benchmark, it will monitor some system information:
     kmsg:      print the kernel startup information
     boot-time: start time diagnosis item
     uptime:    display how long the system has been running
     iostat:    print the time when the data is collected
     heartbeat: provide the heartbeat monitors service
     ...
     other monitors you can see them in $LKP_SRC/include/category/benchmark
  2. If category is functional, it will monitor some system information:
     kmsg:      print the kernel startup information
     heartbeat: provide the heartbeat monitors service
     meminfo:   solid memory usage status or vm usage status
     ...
     you can see the monitors in $LKP_SRC/include/category/functional
