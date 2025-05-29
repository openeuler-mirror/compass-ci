import unittest
from unittest.mock import patch, MagicMock
from container.bisect.bisect_task import BisectTask

class TestBisectTask(unittest.TestCase):

    @patch('container.bisect.bisect_task.ManticoreClient')
    def setUp(self, MockManticoreClient):
        self.mock_client = MockManticoreClient.return_value
        self.bisect_task = BisectTask()

    def test_generate_task_id(self):
        bad_job_id = "12345"
        error_id = "error_67890"
        task_id = self.bisect_task.generate_task_id(bad_job_id, error_id)
        self.assertIsInstance(task_id, int)
        self.assertTrue(0 <= task_id < 2**63)

    def test_add_bisect_task_success(self):
        task = {"bad_job_id": "12345", "error_id": "error_67890"}
        self.mock_client.insert.return_value = True
        result = self.bisect_task.add_bisect_task(task)
        self.assertTrue(result)

    def test_add_bisect_task_failure(self):
        task = {"bad_job_id": "12345", "error_id": "error_67890"}
        self.mock_client.insert.return_value = False
        result = self.bisect_task.add_bisect_task(task)
        self.assertFalse(result)

    def test_set_priority_level(self):
        job_info = {"suite": "check_abi", "repo": "linux", "error_id": "some_error_id"}
        priority = self.bisect_task.set_priority_level(job_info)
        self.assertEqual(priority, 6)  # 根据权重配置计算

if __name__ == '__main__':
    unittest.main()
