"""
在 TaskProcessor 中集成新的 task_marking 模块

示例：替换原有的 _mark_similar_wait_tasks_for_verification
"""

# 在 task_processor.py 顶部导入
from task_marking import TaskMarker

class TaskProcessor:
    def __init__(self):
        # ... 现有初始化代码 ...

        # 添加：初始化 TaskMarker
        self.task_marker = TaskMarker(self.client, self.errid_intelligence)
        logger.info("TaskMarker initialized")

    # 方式1：直接使用新方法（推荐）
    def _mark_similar_wait_tasks_for_verification(self, successful_task: Dict):
        """
        标记相似任务（重构版）
        grep: "mark similar wait tasks"
        """
        return self.task_marker.mark_similar_wait_tasks(successful_task)

    # 方式2：保留旧方法名，内部调用新实现
    # def _mark_similar_wait_tasks_for_verification(self, successful_task: Dict):
    #     """向后兼容：调用新模块"""
    #     from task_marking import mark_similar_wait_tasks_for_verification
    #     return mark_similar_wait_tasks_for_verification(
    #         self.client, self.errid_intelligence, successful_task
    #     )
