"""
 TaskProcessor  task_marking 

： _mark_similar_wait_tasks_for_verification
"""

#  task_processor.py 
from task_marking import TaskMarker

class TaskProcessor:
    def __init__(self):
        # ... initialize ...

        # ：initialize TaskMarker
        self.task_marker = TaskMarker(self.client, self.errid_intelligence)
        logger.info("TaskMarker initialized")

    # 1：（）
    def _mark_similar_wait_tasks_for_verification(self, successful_task: Dict):
        """
        task（）
        grep: "mark similar wait tasks"
        """
        return self.task_marker.mark_similar_wait_tasks(successful_task)

    # 2：，
    # def _mark_similar_wait_tasks_for_verification(self, successful_task: Dict):
    #     """："""
    #     from task_marking import mark_similar_wait_tasks_for_verification
    #     return mark_similar_wait_tasks_for_verification(
    #         self.client, self.errid_intelligence, successful_task
    #     )
