# How Do I View Task Results?

After a test case is executed, you can log in to the https://compass-ci.openeuler.org/jobs to view the execution result.

You can find the task on the website using the suite defined during task submission or the ID returned after the task is submitted, and click the **job\_state** column corresponding to the task to view the task result.

![](./../pictures/jobs.png)

## Result Files

**job.yaml File**

Some fields in the **job.yaml** file are submitted by users, and other fields in the file are automatically added by the platform based on the submitted jobs. This file contains all the parameters required for the test task.

**output File**

The **output** file records the execution process of a test case. The **check\_exit\_code** status code is usually displayed at the end of the file. If the status code is not 0, the test case is incorrect.

**stats.json**

After a test case is executed, a file with the same name as that of the test case is generated. The file records the test commands and standardized output results. Compass-CI parses these files and generates a file with the file name extension **.json**.

The **stats.json** file incorporates all JSON files. The key results of all test commands are included in this file for subsequent comparison and analysis.
