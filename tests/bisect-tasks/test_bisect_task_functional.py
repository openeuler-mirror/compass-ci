import requests
import unittest

class TestBisectTaskAPI(unittest.TestCase):

    BASE_URL = "http://localhost:9999"

    def test_add_bisect_task(self):
        url = f"{self.BASE_URL}/new_bisect_task"
        data = {
            "bad_job_id": "12345",
            "error_id": "error_67890"
        }
        response = requests.post(url, json=data)
        self.assertEqual(response.status_code, 200)
        self.assertIn("Task added successfully", response.json().get("message", ""))

    def test_list_bisect_tasks(self):
        url = f"{self.BASE_URL}/list_bisect_tasks"
        response = requests.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertIn("tasks", response.json())

    def test_list_tasks_by_status(self):
        url = f"{self.BASE_URL}/list_tasks_by_status?status=completed"
        response = requests.get(url)
        self.assertEqual(response.status_code, 200)
        self.assertIn("tasks", response.json())

    def test_delete_failed_tasks(self):
        url = f"{self.BASE_URL}/delete_failed_tasks"
        response = requests.delete(url)
        self.assertEqual(response.status_code, 200)
        self.assertIn("deleted_count", response.json())

if __name__ == '__main__':
    unittest.main()
