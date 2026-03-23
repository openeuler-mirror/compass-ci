#!/usr/bin/env python3
"""Cross-process lock behavior tests for SharedRepoManager pristine file locks."""

import os
import sys
import time
import tempfile
import multiprocessing as mp
import unittest


os.environ.setdefault('WORK_DIR', '/tmp')
os.environ.setdefault('LKP_SRC', '/tmp')
os.environ.setdefault('CCI_SRC', '/tmp')
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'lib'))

from repo_manager import SharedRepoManager
import repo_manager as repo_manager_module


def _lock_worker(pristine_base_dir: str, hold_seconds: float, result_queue):
    # Other core tests monkeypatch bisect_utils helpers globally; pin a stable parser here.
    repo_manager_module.extract_repo_name_from_url = lambda _url: 'kernel'
    manager = SharedRepoManager.__new__(SharedRepoManager)
    manager.PRISTINE_BASE_DIR = pristine_base_dir
    manager.pristine_locks = {}
    manager.pristine_locks_lock = None

    t_enter_req = time.time()
    with manager._pristine_file_lock(
        'https://gitee.com/openeuler/kernel.git',
        os.path.join(pristine_base_dir, 'kernel')
    ):
        t_enter = time.time()
        time.sleep(hold_seconds)
    t_exit = time.time()
    result_queue.put((t_enter_req, t_enter, t_exit))


class TestRepoManagerFileLockMultiprocess(unittest.TestCase):
    def test_file_lock_serializes_two_processes(self):
        repo_manager_module.extract_repo_name_from_url = lambda _url: 'kernel'
        with tempfile.TemporaryDirectory() as tmpdir:
            pristine_base = os.path.join(tmpdir, 'pristine')
            os.makedirs(pristine_base, exist_ok=True)

            q1 = mp.Queue()
            q2 = mp.Queue()
            p1 = mp.Process(target=_lock_worker, args=(pristine_base, 0.35, q1))
            p2 = mp.Process(target=_lock_worker, args=(pristine_base, 0.01, q2))

            p1.start()
            time.sleep(0.05)  # Let p1 likely acquire lock first.
            p2.start()

            p1.join(timeout=5)
            p2.join(timeout=5)
            self.assertEqual(p1.exitcode, 0)
            self.assertEqual(p2.exitcode, 0)

            _req1, enter1, exit1 = q1.get(timeout=1)
            _req2, enter2, _exit2 = q2.get(timeout=1)

            # Process 2 should only enter after process 1 exits (small scheduling slack).
            self.assertGreaterEqual(enter2, exit1 - 0.02)
            # Also ensure p2 really waited (not entering immediately before p1 lock release).
            self.assertGreater(enter2 - enter1, 0.25)


if __name__ == '__main__':
    unittest.main()
