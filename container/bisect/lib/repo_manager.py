#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SharedRepoManager - Gitrepo

Gitrepo，--reference。
task，taskcompleted。

description：
- ，status
- pristine repo--reference
- ：38
- ：status，task
"""

import os
import threading
import subprocess
import shutil
import time
import re
import traceback
import hashlib
import fcntl
from urllib.parse import urlsplit
from contextlib import contextmanager

# log
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger
from config import Config
from bisect_utils import extract_repo_name_from_url


class SharedRepoManager:
    """Gitrepo，+pristine"""

    REPO_BASE_DIR = os.path.join(os.environ['WORK_DIR'], "bisect_repos", "workspaces")
    PRISTINE_BASE_DIR = os.path.join(os.environ['WORK_DIR'], "bisect_repos", "pristine")
    git_sh_path = os.path.join(os.environ.get('LKP_SRC', ''), 'lib/git.sh')

    # Clone concurrency control
    MAX_CONCURRENT_CLONES = Config.BISECT_MAX_CONCURRENT_CLONES

    # Clone timeout configuration
    PRISTINE_CLONE_TIMEOUT = Config.GIT_CLONE_PRISTINE_TIMEOUT
    WORKSPACE_CLONE_TIMEOUT = Config.GIT_CLONE_WORKSPACE_TIMEOUT

    def __init__(self):
        """
        initializerepo - 

        3：
        1. pristine_locks - repoURLpristine
        2. pristine_locks_lock - pristine_locksdict
        3. clone_semaphore - 
        """
        os.makedirs(self.REPO_BASE_DIR, exist_ok=True)
        os.makedirs(self.PRISTINE_BASE_DIR, exist_ok=True)
        logger.info(f"Shared repository workspace root: {self.REPO_BASE_DIR}")
        logger.info(f"Shared repository pristine root: {self.PRISTINE_BASE_DIR}")

        # verifyrepo
        self._cleanup_stale_verify_repos()

        # Pristine repo locks (per-repo-URL)
        self.pristine_locks = {}  # repo_url -> threading.Lock
        self.pristine_locks_lock = threading.Lock()  # Lock for pristine_locks dict
        self.pristine_fetch_timestamps = {}  # repo_url -> last_fetch_time
        self.PRISTINE_FETCH_INTERVAL = Config.GIT_PRISTINE_FETCH_INTERVAL  # config（default1）

        # Clone concurrency control - shared semaphore
        self.clone_semaphore = threading.Semaphore(self.MAX_CONCURRENT_CLONES)
        logger.info(f"Clone semaphore initialized | max_concurrent: {self.MAX_CONCURRENT_CLONES}")

        # Pristine lock observability counters (best effort)
        self._pristine_lock_metrics_lock = threading.Lock()
        self._pristine_lock_metrics = {}

        logger.info("SharedRepoManager initialized (simplified architecture)")

    def _cleanup_stale_verify_repos(self):
        """verifyrepo (verify_xxx  batch_xxx )"""
        try:
            if not os.path.exists(self.REPO_BASE_DIR):
                return

            cleaned_count = 0
            for item in os.listdir(self.REPO_BASE_DIR):
                item_path = os.path.join(self.REPO_BASE_DIR, item)
                if not os.path.isdir(item_path):
                    continue

                #  verify_  batch_ 
                if item.startswith('verify_') or item.startswith('batch_'):
                    try:
                        shutil.rmtree(item_path, ignore_errors=True)
                        cleaned_count += 1
                        logger.debug(f"verifyrepo | path: {item_path}")
                    except Exception as e:
                        logger.warning(f"verifyrepofailed | path: {item_path} | error: {str(e)}")

            if cleaned_count > 0:
                logger.info(f"completed |  {cleaned_count} verifyrepo")

        except Exception as e:
            logger.warning(f"verifyrepofailed: {str(e)}")

    def get_repo_dir(self, task_id, bad_job_id, repo_url):
        """
        getrepo - 

        ：
        1. pristine repo
        2. taskcreateworkspace
        3. --referencepristineworkspace（pristine）

        Returns:
            tuple: (workspace_repo_dir, task_workspace_dir)
        """
        repo_name = extract_repo_name_from_url(repo_url)

        # Ensure pristine repo exists and is up-to-date
        pristine_repo_dir = os.path.join(self.PRISTINE_BASE_DIR, repo_name)

        # Thread-safe access to pristine_locks dictionary
        repo_key = self._canonical_repo_key(repo_url)
        with self.pristine_locks_lock:
            if repo_key not in self.pristine_locks:
                self.pristine_locks[repo_key] = threading.Lock()
                logger.info(f"Created new pristine lock for repo_key: {repo_key}")
            pristine_lock = self.pristine_locks[repo_key]

        # Create task workspace directory (outside lock to reduce lock time)
        task_workspace_dir = os.path.join(self.REPO_BASE_DIR, str(task_id))

        # Clean up if exists (from failed previous attempts)
        if os.path.exists(task_workspace_dir):
            logger.warning(f"Task workspace already exists, cleaning up | task: {task_id} | path: {task_workspace_dir}")
            try:
                shutil.rmtree(task_workspace_dir, ignore_errors=True)
            except Exception as e:
                logger.error(f"Failed to remove existing task workspace: {str(e)}")

        os.makedirs(task_workspace_dir, exist_ok=True)

        # Clone workspace repo with --reference
        workspace_repo_dir = os.path.join(task_workspace_dir, repo_name)

        # Update pristine repo AND clone workspace (both under pristine lock)
        # This prevents pristine from being fetched while we're cloning with --reference
        logger.debug(f"Task {task_id} waiting for pristine lock | repo: {repo_name}")
        with pristine_lock:
            logger.info(f"Task {task_id} acquired pristine lock | repo: {repo_name}")
            with self._pristine_file_lock(repo_url, pristine_repo_dir):
                try:
                    self._ensure_pristine_repo(repo_url, pristine_repo_dir)

                    # Clone workspace while holding pristine lock (prevents race with fetch)
                    logger.info(f"Cloning workspace repo | task: {task_id} | repo: {repo_name}")
                    self._clone_workspace_repo(repo_url, pristine_repo_dir, workspace_repo_dir)
                finally:
                    logger.info(f"Task {task_id} releasing pristine lock | repo: {repo_name}")

        # Clean up stale lock files after clone
        self._cleanup_stale_locks(workspace_repo_dir)

        logger.info(f"Workspace ready | task: {task_id} | repo: {repo_name} | path: {workspace_repo_dir}")
        return workspace_repo_dir, task_workspace_dir

    def release_repo_dir(self, workspace_repo_dir, repo_name=None, instance_id=None, task_id=None):
        """
        repo - 

        deleteworkspace，。
        --reference。

        Args:
            workspace_repo_dir: repo
            repo_name: repo（，）
            instance_id: instanceID（，）
            task_id: taskID（，）
        """
        try:
            if workspace_repo_dir and os.path.exists(workspace_repo_dir):
                # task_idlog
                if not task_id:
                    try:
                        path_parts = workspace_repo_dir.rstrip('/').split('/')
                        if len(path_parts) >= 2 and path_parts[-2].isdigit():
                            task_id = path_parts[-2]
                    except (IndexError, AttributeError):
                        pass

                logger.info(f"Releasing workspace | task: {task_id or 'unknown'} | path: {workspace_repo_dir}")
                shutil.rmtree(workspace_repo_dir, ignore_errors=True)
                logger.info(f"Workspace cleaned | task: {task_id or 'unknown'}")
            else:
                logger.debug(f"Workspace already clean or doesn't exist | path: {workspace_repo_dir}")

        except Exception as e:
            logger.error(f"Failed to release workspace | path: {workspace_repo_dir} | error: {str(e)}")

    @staticmethod
    def _is_git_repo(repo_dir):
        """ git repo (support bare repo)

        Args:
            repo_dir: repo

        Returns:
            bool:  git repo
        """
        if not os.path.exists(repo_dir):
            return False

        # check bare repo ( refs/, objects/ )
        if os.path.exists(os.path.join(repo_dir, "refs")) and \
           os.path.exists(os.path.join(repo_dir, "objects")):
            return True

        # checkrepo ( .git )
        if os.path.exists(os.path.join(repo_dir, ".git")):
            return True

        return False

    @staticmethod
    def _canonical_repo_key(repo_url: str) -> str:
        """Normalize repository URL so equivalent forms share one lock/timestamp key."""
        if not repo_url:
            return ''

        raw = str(repo_url).strip()
        if raw.startswith('git+http://') or raw.startswith('git+https://'):
            raw = raw[4:]
        raw = raw.rstrip('/')

        if '://' in raw:
            parsed = urlsplit(raw)
            path = parsed.path.rstrip('/')
            if path.endswith('.git'):
                path = path[:-4]
            return f"{parsed.scheme.lower()}://{parsed.netloc.lower()}{path}"

        m = re.match(r'^(?:(?P<user>[^@]+)@)?(?P<host>[^:]+):(?P<path>.+)$', raw)
        if m:
            user = m.group('user')
            host = m.group('host').lower()
            path = m.group('path').rstrip('/')
            if path.endswith('.git'):
                path = path[:-4]
            return f"{user + '@' if user else ''}{host}:{path}"

        if raw.endswith('.git'):
            raw = raw[:-4]
        return raw

    def _pristine_lockfile_path(self, repo_url: str, pristine_repo_dir: str) -> str:
        """Build deterministic lock-file path for cross-process pristine operations."""
        repo_name = extract_repo_name_from_url(repo_url) or os.path.basename(pristine_repo_dir.rstrip('/')) or 'repo'
        safe_repo_name = re.sub(r'[^A-Za-z0-9._-]+', '_', repo_name)
        repo_key = self._canonical_repo_key(repo_url)
        key_hash = hashlib.sha1(repo_key.encode('utf-8')).hexdigest()[:16]
        lock_dir = os.path.join(self.PRISTINE_BASE_DIR, '.locks')
        os.makedirs(lock_dir, exist_ok=True)
        return os.path.join(lock_dir, f"{safe_repo_name}-{key_hash}.lock")

    def _record_pristine_lock_metric(self, repo_key: str, wait_seconds: float, hold_seconds: float):
        """Record per-repo lock wait/hold timings for lightweight observability."""
        if not hasattr(self, '_pristine_lock_metrics'):
            self._pristine_lock_metrics = {}
        if not hasattr(self, '_pristine_lock_metrics_lock'):
            self._pristine_lock_metrics_lock = threading.Lock()

        with self._pristine_lock_metrics_lock:
            metric = self._pristine_lock_metrics.setdefault(repo_key, {
                'acquire_count': 0,
                'wait_seconds_total': 0.0,
                'hold_seconds_total': 0.0,
                'wait_seconds_max': 0.0,
                'hold_seconds_max': 0.0,
                'last_acquired_at': 0,
            })
            metric['acquire_count'] += 1
            metric['wait_seconds_total'] += max(0.0, wait_seconds)
            metric['hold_seconds_total'] += max(0.0, hold_seconds)
            metric['wait_seconds_max'] = max(metric['wait_seconds_max'], wait_seconds)
            metric['hold_seconds_max'] = max(metric['hold_seconds_max'], hold_seconds)
            metric['last_acquired_at'] = int(time.time())

    def get_pristine_lock_metrics(self) -> dict:
        """Return snapshot of pristine lock observability metrics."""
        if not hasattr(self, '_pristine_lock_metrics'):
            return {'repos': 0, 'total_acquire_count': 0, 'per_repo': {}}
        if not hasattr(self, '_pristine_lock_metrics_lock'):
            self._pristine_lock_metrics_lock = threading.Lock()

        with self._pristine_lock_metrics_lock:
            per_repo = {}
            total_acquire_count = 0
            for key, value in self._pristine_lock_metrics.items():
                total_acquire_count += int(value.get('acquire_count', 0))
                per_repo[key] = dict(value)
            return {
                'repos': len(per_repo),
                'total_acquire_count': total_acquire_count,
                'per_repo': per_repo
            }

    @contextmanager
    def _pristine_file_lock(self, repo_url: str, pristine_repo_dir: str):
        """Cross-process advisory lock for pristine repo operations."""
        repo_key = self._canonical_repo_key(repo_url)
        lock_path = self._pristine_lockfile_path(repo_url, pristine_repo_dir)
        fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            with os.fdopen(fd, 'a+') as lock_file:
                logger.debug(f"Waiting for file lock | path: {lock_path}")
                wait_start = time.time()
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                acquired_at = time.time()
                logger.debug(f"Acquired file lock | path: {lock_path}")
                try:
                    yield
                finally:
                    released_at = time.time()
                    self._record_pristine_lock_metric(
                        repo_key,
                        acquired_at - wait_start,
                        released_at - acquired_at
                    )
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    logger.debug(f"Released file lock | path: {lock_path}")
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

    def _ensure_pristine_repo(self, repo_url, pristine_repo_dir):
        """repostatus（）"""
        repo_name = extract_repo_name_from_url(repo_url)
        repo_key = self._canonical_repo_key(repo_url)
        current_time = time.time()

        if not self._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, cloning | repo: {repo_name} | path: {pristine_repo_dir}")
            # Clean up any partial/corrupted directory before cloning
            if os.path.exists(pristine_repo_dir):
                logger.warning(f"Found partial pristine directory, cleaning up | path: {pristine_repo_dir}")
                shutil.rmtree(pristine_repo_dir, ignore_errors=True)
            self._clone_repo_atomic(repo_url, pristine_repo_dir)
            logger.info(f"Pristine repo cloned | repo: {repo_name}")
            #  fetch 
            self.pristine_fetch_timestamps[repo_key] = current_time
        else:
            # check fetch（duplicate fetch）
            last_fetch_time = self.pristine_fetch_timestamps.get(repo_key, 0)
            time_since_last_fetch = current_time - last_fetch_time

            if time_since_last_fetch < self.PRISTINE_FETCH_INTERVAL:
                logger.info(f"Pristine repo recently fetched, skipping | repo: {repo_name} | "
                           f"last_fetch: {time_since_last_fetch:.0f}s ago")
                return

            logger.info(f"Pristine repo found, fetching updates | repo: {repo_name} | path: {pristine_repo_dir} | "
                       f"last_fetch: {time_since_last_fetch:.0f}s ago")
            try:
                self._fetch_repo(pristine_repo_dir)
                logger.info(f"Pristine repo updated | repo: {repo_name}")
                #  fetch 
                self.pristine_fetch_timestamps[repo_key] = current_time
            except Exception as e:
                logger.warning(f"Pristine repo fetch failed, will recreate | repo: {repo_name} | error: {str(e)}")
                # fetchfailed，
                self._recreate_pristine_repo_atomic(repo_url, pristine_repo_dir)
                logger.info(f"Pristine repo recreated | repo: {repo_name}")
                #  fetch 
                self.pristine_fetch_timestamps[repo_key] = current_time

    def _clone_repo_atomic(self, repo_url, repo_dir):
        """ pristine bare repo

        ，success。
         repo_dir not found，repo。
        """
        # Sanitize URL before attempting to clone
        if repo_url.startswith("git+http"):
            repo_url = repo_url.replace("git+", "", 1)

        repo_name = extract_repo_name_from_url(repo_url)
        temp_dir = f"{repo_dir}.tmp.{int(time.time())}"

        # count
        logger.info(f"Waiting for clone slot... | repo: {repo_name} | max_concurrent: {self.MAX_CONCURRENT_CLONES}")
        with self.clone_semaphore:
            logger.info(f"Clone slot acquired | repo: {repo_name} | starting atomic pristine clone")

            retries = 3
            for i in range(retries):
                try:
                    # Clean up temp directory before each attempt
                    if os.path.exists(temp_dir):
                        shutil.rmtree(temp_dir, ignore_errors=True)

                    # Clone to temp directory
                    logger.info(f"Cloning to temp directory (attempt {i+1}/{retries}) | temp: {temp_dir}")
                    subprocess.run(
                        ['git', 'clone', '--bare', repo_url, temp_dir],
                        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.PRISTINE_CLONE_TIMEOUT
                    )

                    # Verify the clone is valid
                    if not self._is_git_repo(temp_dir):
                        raise RuntimeError(f"Cloned repo is invalid: {temp_dir}")

                    # Atomic rename: remove old and rename temp to target
                    if os.path.exists(repo_dir):
                        shutil.rmtree(repo_dir, ignore_errors=True)
                    os.rename(temp_dir, repo_dir)

                    # Bare clone doesn't set fetch refspec — configure it
                    # so that subsequent `git fetch origin` pulls all refs + tags
                    subprocess.run(
                        ['git', '-C', repo_dir, 'config', 'remote.origin.fetch', '+refs/*:refs/*'],
                        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
                    )

                    logger.info(f"Pristine bare repository cloned atomically | repo: {repo_name}")
                    return

                except subprocess.CalledProcessError as e:
                    stderr_output = e.stderr.decode() if e.stderr else "No stderr"
                    logger.warning(f"Clone attempt {i+1}/{retries} failed | repo: {repo_name} | stderr: {stderr_output[:200]}")

                    if i == retries - 1:
                        logger.error(f"All clone attempts failed for {repo_url}")
                        # Clean up temp dir
                        if os.path.exists(temp_dir):
                            shutil.rmtree(temp_dir, ignore_errors=True)
                        raise

                    time.sleep(2 ** i)  # ：1s, 2s, 4s

                except Exception as e:
                    logger.error(f"Unexpected error during atomic clone | repo: {repo_name} | error: {str(e)}")
                    # Clean up temp dir
                    if os.path.exists(temp_dir):
                        shutil.rmtree(temp_dir, ignore_errors=True)
                    raise

    def _recreate_pristine_repo_atomic(self, repo_url, repo_dir):
        """ pristine repo

        ，success。
        ，repo。
        """
        repo_name = extract_repo_name_from_url(repo_url)
        temp_dir = f"{repo_dir}.new.{int(time.time())}"
        old_dir = f"{repo_dir}.old.{int(time.time())}"

        try:
            # 
            self._clone_repo_atomic(repo_url, temp_dir)

            # ： ->  -> delete
            if os.path.exists(repo_dir):
                os.rename(repo_dir, old_dir)

            os.rename(temp_dir, repo_dir)

            # 
            if os.path.exists(old_dir):
                shutil.rmtree(old_dir, ignore_errors=True)

            logger.info(f"Pristine repo recreated atomically | repo: {repo_name}")

        except Exception as e:
            # （）
            if os.path.exists(old_dir) and not os.path.exists(repo_dir):
                try:
                    os.rename(old_dir, repo_dir)
                    logger.info(f"Restored old pristine repo after failure | repo: {repo_name}")
                except OSError:
                    pass

            # 
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir, ignore_errors=True)

            raise

    def _clone_repo(self, repo_url, repo_dir):
        """ bare repo（，）"""
        self._clone_repo_atomic(repo_url, repo_dir)

    def _fetch_repo(self, repo_dir):
        """Fetch updates for bare pristine repository"""
        try:
            # Ensure refspec exists (may be missing on old bare clones)
            result = subprocess.run(
                ['git', '-C', repo_dir, 'config', 'remote.origin.fetch'],
                capture_output=True, text=True
            )
            if not result.stdout.strip():
                logger.info(f"Setting missing fetch refspec | path: {repo_dir}")
                subprocess.run(
                    ['git', '-C', repo_dir, 'config', 'remote.origin.fetch', '+refs/*:refs/*'],
                    check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )

            subprocess.run(
                ['git', '-C', repo_dir, 'fetch', 'origin'],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=120
            )
            logger.info(f"Pristine bare repository updated successfully | path: {repo_dir}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to fetch updates for pristine repo {repo_dir}: {e.stderr.decode()}")
            raise

    def _clone_workspace_repo(self, repo_url, pristine_repo_dir, workspace_repo_dir):
        """ --bare --reference  bare  - """
        repo_name = extract_repo_name_from_url(repo_url)

        # count
        logger.info(f"Waiting for clone slot... | repo: {repo_name} | max_concurrent: {self.MAX_CONCURRENT_CLONES}")
        with self.clone_semaphore:
            logger.info(f"Clone slot acquired | repo: {repo_name} | starting bare workspace clone")

            # ： 3 
            max_retries = 3
            last_error = None

            for attempt in range(1, max_retries + 1):
                try:
                    self._clone_workspace_repo_internal(repo_url, pristine_repo_dir, workspace_repo_dir)
                    return  # success
                except Exception as e:
                    last_error = e
                    logger.warning(f"Clone attempt {attempt}/{max_retries} failed | repo: {repo_name} | error: {str(e)}")

                    # failed
                    if os.path.exists(workspace_repo_dir):
                        shutil.rmtree(workspace_repo_dir, ignore_errors=True)

                    if attempt < max_retries:
                        wait_time = attempt * 2  # ：2s, 4s
                        logger.info(f"Waiting {wait_time}s before retry...")
                        time.sleep(wait_time)

            # failed
            logger.error(f"All {max_retries} clone attempts failed | repo: {repo_name}")
            raise last_error

    def _clone_workspace_repo_internal(self, repo_url, pristine_repo_dir, workspace_repo_dir):
        """ --bare --reference  bare  - （）

         --bare --reference  bare pristine repo :
        -  pristine bare repo，
        - （）
        - ， IO
        - bare reposupport git bisect 
        """
        repo_name = extract_repo_name_from_url(repo_url)

        # （failed）
        if os.path.exists(workspace_repo_dir):
            logger.warning(f"Target directory exists before clone, cleaning up | path: {workspace_repo_dir}")
            shutil.rmtree(workspace_repo_dir)
            logger.info(f"Pre-clone cleanup successful | path: {workspace_repo_dir}")

        logger.info(f"Starting bare clone with --reference: {repo_name} -> {workspace_repo_dir}")
        start_time = time.time()

        #  --reference 
        result = subprocess.run(
            ['git', 'clone', '--bare', '--reference', pristine_repo_dir, repo_url, workspace_repo_dir],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.WORKSPACE_CLONE_TIMEOUT
        )

        if result.returncode == 0:
            clone_time = time.time() - start_time
            logger.info(f"Bare clone with --reference successful | repo: {repo_name} | time: {clone_time:.1f}s")
            return

        # --reference failed，
        stderr_output = result.stderr.decode() if result.stderr else "No stderr"
        logger.warning(f"Bare clone with --reference failed | repo: {repo_name} | stderr: {stderr_output[:300]}")

        # failed
        if os.path.exists(workspace_repo_dir):
            shutil.rmtree(workspace_repo_dir, ignore_errors=True)

        #  bare  ( reference)
        logger.info(f"Falling back to standard bare clone: {repo_name}")
        result = subprocess.run(
            ['git', 'clone', '--bare', repo_url, workspace_repo_dir],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.WORKSPACE_CLONE_TIMEOUT
        )

        if result.returncode == 0:
            clone_time = time.time() - start_time
            logger.info(f"Standard bare clone successful | repo: {repo_name} | time: {clone_time:.1f}s")
            return

        # failed
        fallback_stderr = result.stderr.decode() if result.stderr else "No stderr"
        logger.error(f"Standard bare clone also failed | repo: {repo_name} | stderr: {fallback_stderr[:300]}")

        # 
        if os.path.exists(workspace_repo_dir):
            shutil.rmtree(workspace_repo_dir, ignore_errors=True)

        raise RuntimeError(f"All clone methods failed for {repo_name}: {fallback_stderr[:200]}")

    def _cleanup_stale_locks(self, repo_dir):
        """
         Git repofile (support bare repo)

        Git  .lock file，。
        """
        #  git 
        if os.path.exists(os.path.join(repo_dir, '.git')):
            # repo
            git_dir = os.path.join(repo_dir, '.git')
        elif os.path.exists(os.path.join(repo_dir, 'refs')) and \
             os.path.exists(os.path.join(repo_dir, 'objects')):
            # bare repo, git 
            git_dir = repo_dir
        else:
            logger.warning(f"Not a valid git repository, skipping lock cleanup | path: {repo_dir}")
            return

        lock_files = []

        # Common lock files
        common_locks = [
            'index.lock',
            'HEAD.lock',
            'config.lock',
            'packed-refs.lock',
            'FETCH_HEAD.lock',
            'ORIG_HEAD.lock',
        ]

        for lock_file in common_locks:
            lock_path = os.path.join(git_dir, lock_file)
            if os.path.exists(lock_path):
                lock_files.append(lock_path)

        # Find all .lock files in refs directory
        refs_dir = os.path.join(git_dir, 'refs')
        if os.path.exists(refs_dir):
            for root, dirs, files in os.walk(refs_dir):
                for file in files:
                    if file.endswith('.lock'):
                        lock_files.append(os.path.join(root, file))

        # Remove lock files
        if lock_files:
            logger.warning(f"Found {len(lock_files)} stale lock file(s) in {repo_dir}")
            for lock_path in lock_files:
                try:
                    os.remove(lock_path)
                    logger.info(f"Removed stale lock: {lock_path}")
                except Exception as e:
                    logger.warning(f"Failed to remove lock file {lock_path}: {str(e)}")

    def _recover_checkout(self, repo_dir):
        """
        failed checkout 

        Returns:
            bool: True if recovery successful, False otherwise
        """
        max_retries = 3
        base_delay = 5  # （）

        # First, clean up any stale locks
        self._cleanup_stale_locks(repo_dir)

        for attempt in range(max_retries):
            try:
                logger.info(f"Checkout recovery attempt {attempt + 1}/{max_retries} | path: {repo_dir}")

                #  IO 
                if attempt > 0:
                    delay = base_delay * (2 ** (attempt - 1))
                    logger.info(f"Waiting {delay}s for IO pressure to decrease...")
                    time.sleep(delay)

                #  reset + restore 
                subprocess.run(
                    ['git', '-C', repo_dir, 'reset', '--hard', 'HEAD'],
                    check=True, capture_output=True, timeout=300
                )

                # verify checkout success
                result = subprocess.run(
                    ['git', '-C', repo_dir, 'status'],
                    check=True, capture_output=True, timeout=30
                )

                status_output = result.stdout.decode()
                if "nothing to commit" in status_output or "working tree clean" in status_output:
                    logger.info(f"Checkout recovery successful on attempt {attempt + 1} | path: {repo_dir}")
                    return True

            except subprocess.CalledProcessError as e:
                logger.warning(f"Checkout recovery attempt {attempt + 1} failed | error: {e.stderr.decode()[:100]}")
            except subprocess.TimeoutExpired:
                logger.warning(f"Checkout recovery attempt {attempt + 1} timed out")
            except Exception as e:
                logger.warning(f"Checkout recovery attempt {attempt + 1} error: {str(e)}")

        logger.error(f"All checkout recovery attempts failed | path: {repo_dir}")
        return False

    @contextmanager
    def get_repo_context(self, task_id, bad_job_id, repo_url):
        """
        Context manager for automatic repository acquisition and release

        Usage:
            with repo_manager.get_repo_context(task_id, bad_job_id, repo_url) as (repo_dir, task_dir):
                # Use repo_dir for git operations
                pass
            # Repository automatically cleaned up
        """
        workspace_repo_dir = None
        task_workspace_dir = None

        try:
            # Acquire repository
            workspace_repo_dir, task_workspace_dir = self.get_repo_dir(task_id, bad_job_id, repo_url)

            yield workspace_repo_dir, task_workspace_dir

        finally:
            # Always clean up workspace
            if workspace_repo_dir and os.path.exists(workspace_repo_dir):
                try:
                    self.release_repo_dir(workspace_repo_dir)
                except Exception as e:
                    logger.error(f"Failed to release repository in context manager | error: {str(e)}")

    def cleanup_old_workspaces(self, max_age_days=7):
        """
        repo

        ：deletetask workspace

        Args:
            max_age_days: 

        Returns:
            tuple: (deleted_count, skipped_count)
        """
        try:
            workspaces_dir = self.REPO_BASE_DIR
            if not os.path.exists(workspaces_dir):
                logger.info("Workspaces directory does not exist, skipping cleanup")
                return 0, 0

            deleted_count = 0
            skipped_count = 0
            max_age_seconds = max_age_days * 86400

            # task
            for task_id in os.listdir(workspaces_dir):
                task_dir = os.path.join(workspaces_dir, task_id)

                if not os.path.isdir(task_dir):
                    continue

                # check
                try:
                    last_used = os.path.getmtime(task_dir)
                    age_seconds = time.time() - last_used
                except OSError:
                    skipped_count += 1
                    continue

                if age_seconds <= max_age_seconds:
                    skipped_count += 1
                    continue

                age_hours = age_seconds / 3600
                logger.info(f"Cleaning old task workspace | task: {task_id} | age: {age_hours:.1f} hours")

                try:
                    shutil.rmtree(task_dir, ignore_errors=True)
                    deleted_count += 1
                except Exception as e:
                    logger.error(f"Failed to clean task workspace | task: {task_id} | error: {str(e)}")

            logger.info(f"Workspace cleanup complete | deleted: {deleted_count} | skipped: {skipped_count}")
            return deleted_count, skipped_count

        except Exception as e:
            logger.error(f"Workspace cleanup failed | error: {str(e)}")
            return 0, 0

    def get_pool_stats(self):
        """
        getstats - 

        workspacestats，status

        Returns:
            dict: stats
        """
        stats = {
            'architecture': 'simplified',
            'pristine_repos': len(self.pristine_locks),
            'max_concurrent_clones': self.MAX_CONCURRENT_CLONES
        }

        # statsworkspacecount
        try:
            if os.path.exists(self.REPO_BASE_DIR):
                active_workspaces = len([d for d in os.listdir(self.REPO_BASE_DIR)
                                        if os.path.isdir(os.path.join(self.REPO_BASE_DIR, d))])
                stats['active_workspaces'] = active_workspaces
        except OSError:
            stats['active_workspaces'] = 0

        return stats
