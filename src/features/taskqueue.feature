Feature: TaskQueue

  Scenario: add a task without id
    Given has a task
    """
    {"suite":"test01", "tbox_group":"host"}
    """
    When call with post api "add?queue=scheduler/host" task
    Then return with task id > 0

#  Scenario: add a task with reuse id
#    {"suite":"test01", "id":1, "tbox_group":"host"}
#  Scenario: add a task with id large then global one
#    {"suite":"test01", "id":65536, "tbox_group":"host"}
