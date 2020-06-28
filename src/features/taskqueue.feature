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

  Scenario: consume an exists task
    Given has a task
    """
    {"suite":"test01", "tbox_group":"host"}
    """
    And call with post api "add?queue=scheduler/host" task
    When call with put api "consume?queue=scheduler/host"
    Then return with task tbox_group == "host"
