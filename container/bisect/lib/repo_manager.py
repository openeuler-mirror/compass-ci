#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
SharedRepoManager - 简化版Git仓库管理器

管理共享Git仓库，使用--reference优化空间占用。
每个任务使用独立的临时克隆，任务完成后清理。

重构说明：
- 移除复杂的池化机制，消除状态同步问题
- 保留pristine repo缓存和--reference优化
- 大幅简化锁机制：仅3个锁而非8个
- 提升鲁棒性：无共享状态，任务间完全隔离
"""

import os
import threading
import subprocess
import shutil
import time
import re
import traceback
from contextlib import contextmanager

# 导入日志系统
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'lib'))
from log_config import logger
from config import Config
from bisect_utils import extract_repo_name_from_url


class SharedRepoManager:
    """管理共享Git仓库，使用临时克隆+pristine缓存的简化架构"""

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
        初始化仓库管理器 - 简化版本

        仅保留必要的3个锁：
        1. pristine_locks - 每个仓库URL的pristine更新锁
        2. pristine_locks_lock - pristine_locks字典的访问锁
        3. clone_semaphore - 限制并发克隆数
        """
        os.makedirs(self.REPO_BASE_DIR, exist_ok=True)
        os.makedirs(self.PRISTINE_BASE_DIR, exist_ok=True)
        logger.info(f"Shared repository workspace root: {self.REPO_BASE_DIR}")
        logger.info(f"Shared repository pristine root: {self.PRISTINE_BASE_DIR}")

        # 启动时清理旧的验证仓库
        self._cleanup_stale_verify_repos()

        # Pristine repo locks (per-repo-URL)
        self.pristine_locks = {}  # repo_url -> threading.Lock
        self.pristine_locks_lock = threading.Lock()  # Lock for pristine_locks dict
        self.pristine_fetch_timestamps = {}  # repo_url -> last_fetch_time
        self.PRISTINE_FETCH_INTERVAL = Config.GIT_PRISTINE_FETCH_INTERVAL  # 从配置读取（默认1小时）

        # Clone concurrency control - shared semaphore
        self.clone_semaphore = threading.Semaphore(self.MAX_CONCURRENT_CLONES)
        logger.info(f"Clone semaphore initialized | max_concurrent: {self.MAX_CONCURRENT_CLONES}")

        logger.info("SharedRepoManager initialized (simplified architecture)")

    def _cleanup_stale_verify_repos(self):
        """启动时清理旧的验证仓库 (verify_xxx 和 batch_xxx 目录)"""
        try:
            if not os.path.exists(self.REPO_BASE_DIR):
                return

            cleaned_count = 0
            for item in os.listdir(self.REPO_BASE_DIR):
                item_path = os.path.join(self.REPO_BASE_DIR, item)
                if not os.path.isdir(item_path):
                    continue

                # 清理 verify_ 前缀和 batch_ 前缀的目录
                if item.startswith('verify_') or item.startswith('batch_'):
                    try:
                        shutil.rmtree(item_path, ignore_errors=True)
                        cleaned_count += 1
                        logger.debug(f"清理旧验证仓库 | path: {item_path}")
                    except Exception as e:
                        logger.warning(f"清理验证仓库失败 | path: {item_path} | error: {str(e)}")

            if cleaned_count > 0:
                logger.info(f"启动清理完成 | 清理了 {cleaned_count} 个旧验证仓库")

        except Exception as e:
            logger.warning(f"启动清理验证仓库失败: {str(e)}")

    def get_repo_dir(self, task_id, bad_job_id, repo_url):
        """
        获取仓库工作目录 - 简化版本

        流程：
        1. 确保pristine repo存在且最新
        2. 为任务创建独立的workspace目录
        3. 使用--reference从pristine克隆到workspace（在pristine锁保护下）

        Returns:
            tuple: (workspace_repo_dir, task_workspace_dir)
        """
        repo_name = extract_repo_name_from_url(repo_url)

        # Ensure pristine repo exists and is up-to-date
        pristine_repo_dir = os.path.join(self.PRISTINE_BASE_DIR, repo_name)

        # Thread-safe access to pristine_locks dictionary
        with self.pristine_locks_lock:
            if repo_url not in self.pristine_locks:
                self.pristine_locks[repo_url] = threading.Lock()
                logger.info(f"Created new pristine lock for repo_url: {repo_url}")
            pristine_lock = self.pristine_locks[repo_url]

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
        释放仓库目录 - 简化版本

        直接删除workspace目录，无需复杂的回收逻辑。
        --reference机制保证了空间效率。

        Args:
            workspace_repo_dir: 工作区仓库目录
            repo_name: 仓库名称（兼容参数，可选）
            instance_id: 实例ID（兼容参数，可选）
            task_id: 任务ID（兼容参数，可选）
        """
        try:
            if workspace_repo_dir and os.path.exists(workspace_repo_dir):
                # 尝试从路径推断task_id用于日志
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
        """检测目录是否是有效的 git 仓库 (支持 bare 和普通仓库)

        Args:
            repo_dir: 仓库目录路径

        Returns:
            bool: 是否是有效的 git 仓库
        """
        if not os.path.exists(repo_dir):
            return False

        # 检查是否是 bare 仓库 (直接包含 refs/, objects/ 等)
        if os.path.exists(os.path.join(repo_dir, "refs")) and \
           os.path.exists(os.path.join(repo_dir, "objects")):
            return True

        # 检查是否是普通仓库 (包含 .git 目录)
        if os.path.exists(os.path.join(repo_dir, ".git")):
            return True

        return False

    def _ensure_pristine_repo(self, repo_url, pristine_repo_dir):
        """确保参考仓库存在且是最新状态（原子化操作）"""
        repo_name = extract_repo_name_from_url(repo_url)
        current_time = time.time()

        if not self._is_git_repo(pristine_repo_dir):
            logger.info(f"Pristine repo not found, cloning | repo: {repo_name} | path: {pristine_repo_dir}")
            # Clean up any partial/corrupted directory before cloning
            if os.path.exists(pristine_repo_dir):
                logger.warning(f"Found partial pristine directory, cleaning up | path: {pristine_repo_dir}")
                shutil.rmtree(pristine_repo_dir, ignore_errors=True)
            self._clone_repo_atomic(repo_url, pristine_repo_dir)
            logger.info(f"Pristine repo cloned | repo: {repo_name}")
            # 更新 fetch 时间戳
            self.pristine_fetch_timestamps[repo_url] = current_time
        else:
            # 检查是否需要 fetch（避免短时间内重复 fetch）
            last_fetch_time = self.pristine_fetch_timestamps.get(repo_url, 0)
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
                # 更新 fetch 时间戳
                self.pristine_fetch_timestamps[repo_url] = current_time
            except Exception as e:
                logger.warning(f"Pristine repo fetch failed, will recreate | repo: {repo_name} | error: {str(e)}")
                # 如果fetch失败，使用原子化方式重建
                self._recreate_pristine_repo_atomic(repo_url, pristine_repo_dir)
                logger.info(f"Pristine repo recreated | repo: {repo_name}")
                # 更新 fetch 时间戳
                self.pristine_fetch_timestamps[repo_url] = current_time

    def _clone_repo_atomic(self, repo_url, repo_dir):
        """原子化克隆 pristine bare 仓库

        先克隆到临时目录，成功后再原子重命名到目标目录。
        这确保 repo_dir 要么不存在，要么是完整可用的仓库。
        """
        # Sanitize URL before attempting to clone
        if repo_url.startswith("git+http"):
            repo_url = repo_url.replace("git+", "", 1)

        repo_name = extract_repo_name_from_url(repo_url)
        temp_dir = f"{repo_dir}.tmp.{int(time.time())}"

        # 使用信号量限制并发克隆数量
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

                    time.sleep(2 ** i)  # 指数退避：1s, 2s, 4s

                except Exception as e:
                    logger.error(f"Unexpected error during atomic clone | repo: {repo_name} | error: {str(e)}")
                    # Clean up temp dir
                    if os.path.exists(temp_dir):
                        shutil.rmtree(temp_dir, ignore_errors=True)
                    raise

    def _recreate_pristine_repo_atomic(self, repo_url, repo_dir):
        """原子化重建 pristine 仓库

        先克隆到新目录，成功后再替换旧目录。
        这确保在重建过程中，旧仓库仍然可用。
        """
        repo_name = extract_repo_name_from_url(repo_url)
        temp_dir = f"{repo_dir}.new.{int(time.time())}"
        old_dir = f"{repo_dir}.old.{int(time.time())}"

        try:
            # 克隆到临时目录
            self._clone_repo_atomic(repo_url, temp_dir)

            # 原子替换：旧目录改名 -> 临时目录改名到目标 -> 删除旧目录
            if os.path.exists(repo_dir):
                os.rename(repo_dir, old_dir)

            os.rename(temp_dir, repo_dir)

            # 异步清理旧目录
            if os.path.exists(old_dir):
                shutil.rmtree(old_dir, ignore_errors=True)

            logger.info(f"Pristine repo recreated atomically | repo: {repo_name}")

        except Exception as e:
            # 恢复旧目录（如果存在）
            if os.path.exists(old_dir) and not os.path.exists(repo_dir):
                try:
                    os.rename(old_dir, repo_dir)
                    logger.info(f"Restored old pristine repo after failure | repo: {repo_name}")
                except OSError:
                    pass

            # 清理临时目录
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir, ignore_errors=True)

            raise

    def _clone_repo(self, repo_url, repo_dir):
        """克隆一个 bare 仓库（向后兼容，调用原子化版本）"""
        self._clone_repo_atomic(repo_url, repo_dir)

    def _fetch_repo(self, repo_dir):
        """在 bare 仓库中执行 git fetch"""
        try:
            subprocess.run(
                ['git', '-C', repo_dir, 'fetch', 'origin'],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            logger.info(f"Pristine bare repository updated successfully | Path: {repo_dir}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to fetch updates for pristine repo {repo_dir}: {e.stderr.decode()}")
            raise

    def _clone_workspace_repo(self, repo_url, pristine_repo_dir, workspace_repo_dir):
        """使用 --bare --reference 克隆一个 bare 工作区 - 带信号量控制和重试"""
        repo_name = extract_repo_name_from_url(repo_url)

        # 使用信号量限制并发克隆数量
        logger.info(f"Waiting for clone slot... | repo: {repo_name} | max_concurrent: {self.MAX_CONCURRENT_CLONES}")
        with self.clone_semaphore:
            logger.info(f"Clone slot acquired | repo: {repo_name} | starting bare workspace clone")

            # 重试机制：最多尝试 3 次
            max_retries = 3
            last_error = None

            for attempt in range(1, max_retries + 1):
                try:
                    self._clone_workspace_repo_internal(repo_url, pristine_repo_dir, workspace_repo_dir)
                    return  # 成功则直接返回
                except Exception as e:
                    last_error = e
                    logger.warning(f"Clone attempt {attempt}/{max_retries} failed | repo: {repo_name} | error: {str(e)}")

                    # 清理失败的目录
                    if os.path.exists(workspace_repo_dir):
                        shutil.rmtree(workspace_repo_dir, ignore_errors=True)

                    if attempt < max_retries:
                        wait_time = attempt * 2  # 递增等待：2s, 4s
                        logger.info(f"Waiting {wait_time}s before retry...")
                        time.sleep(wait_time)

            # 所有重试都失败
            logger.error(f"All {max_retries} clone attempts failed | repo: {repo_name}")
            raise last_error

    def _clone_workspace_repo_internal(self, repo_url, pristine_repo_dir, workspace_repo_dir):
        """使用 --bare --reference 克隆 bare 工作区 - 内部实现（单次尝试）

        使用 --bare --reference 引用 bare pristine repo 的优势:
        - 对象引用 pristine bare repo，减少磁盘占用
        - 克隆速度快（仅复制差异对象）
        - 无工作树，大幅减少磁盘 IO
        - bare 仓库支持 git bisect 操作
        """
        repo_name = extract_repo_name_from_url(repo_url)

        # 克隆前先清理目标目录（防止残留目录导致失败）
        if os.path.exists(workspace_repo_dir):
            logger.warning(f"Target directory exists before clone, cleaning up | path: {workspace_repo_dir}")
            shutil.rmtree(workspace_repo_dir)
            logger.info(f"Pre-clone cleanup successful | path: {workspace_repo_dir}")

        logger.info(f"Starting bare clone with --reference: {repo_name} -> {workspace_repo_dir}")
        start_time = time.time()

        # 尝试使用 --reference 克隆
        result = subprocess.run(
            ['git', 'clone', '--bare', '--reference', pristine_repo_dir, repo_url, workspace_repo_dir],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.WORKSPACE_CLONE_TIMEOUT
        )

        if result.returncode == 0:
            clone_time = time.time() - start_time
            logger.info(f"Bare clone with --reference successful | repo: {repo_name} | time: {clone_time:.1f}s")
            return

        # --reference 克隆失败，尝试普通克隆
        stderr_output = result.stderr.decode() if result.stderr else "No stderr"
        logger.warning(f"Bare clone with --reference failed | repo: {repo_name} | stderr: {stderr_output[:300]}")

        # 清理失败的目录
        if os.path.exists(workspace_repo_dir):
            shutil.rmtree(workspace_repo_dir, ignore_errors=True)

        # 回退到普通 bare 克隆 (不使用 reference)
        logger.info(f"Falling back to standard bare clone: {repo_name}")
        result = subprocess.run(
            ['git', 'clone', '--bare', repo_url, workspace_repo_dir],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=self.WORKSPACE_CLONE_TIMEOUT
        )

        if result.returncode == 0:
            clone_time = time.time() - start_time
            logger.info(f"Standard bare clone successful | repo: {repo_name} | time: {clone_time:.1f}s")
            return

        # 普通克隆也失败
        fallback_stderr = result.stderr.decode() if result.stderr else "No stderr"
        logger.error(f"Standard bare clone also failed | repo: {repo_name} | stderr: {fallback_stderr[:300]}")

        # 清理
        if os.path.exists(workspace_repo_dir):
            shutil.rmtree(workspace_repo_dir, ignore_errors=True)

        raise RuntimeError(f"All clone methods failed for {repo_name}: {fallback_stderr[:200]}")

    def _cleanup_stale_locks(self, repo_dir):
        """
        清理 Git 仓库中的过期锁文件 (支持 bare 和普通仓库)

        Git 操作被中断时会留下 .lock 文件，阻止后续操作。
        """
        # 确定 git 目录位置
        if os.path.exists(os.path.join(repo_dir, '.git')):
            # 普通仓库
            git_dir = os.path.join(repo_dir, '.git')
        elif os.path.exists(os.path.join(repo_dir, 'refs')) and \
             os.path.exists(os.path.join(repo_dir, 'objects')):
            # bare 仓库,整个目录就是 git 目录
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
        尝试恢复失败的 checkout 操作

        Returns:
            bool: True if recovery successful, False otherwise
        """
        max_retries = 3
        base_delay = 5  # 基础等待时间（秒）

        # First, clean up any stale locks
        self._cleanup_stale_locks(repo_dir)

        for attempt in range(max_retries):
            try:
                logger.info(f"Checkout recovery attempt {attempt + 1}/{max_retries} | path: {repo_dir}")

                # 等待 IO 压力降低
                if attempt > 0:
                    delay = base_delay * (2 ** (attempt - 1))
                    logger.info(f"Waiting {delay}s for IO pressure to decrease...")
                    time.sleep(delay)

                # 尝试 reset + restore 恢复工作树
                subprocess.run(
                    ['git', '-C', repo_dir, 'reset', '--hard', 'HEAD'],
                    check=True, capture_output=True, timeout=300
                )

                # 验证 checkout 是否成功
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
        清理超过指定天数未使用的工作区仓库

        简化版：直接删除旧的task workspace目录

        Args:
            max_age_days: 超过多少天的目录会被清理

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

            # 遍历所有任务目录
            for task_id in os.listdir(workspaces_dir):
                task_dir = os.path.join(workspaces_dir, task_id)

                if not os.path.isdir(task_dir):
                    continue

                # 检查目录最后使用时间
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
        获取统计信息 - 简化版

        仅返回基本的workspace统计，不再有池化状态

        Returns:
            dict: 统计信息
        """
        stats = {
            'architecture': 'simplified',
            'pristine_repos': len(self.pristine_locks),
            'max_concurrent_clones': self.MAX_CONCURRENT_CLONES
        }

        # 统计当前活跃的workspace数量
        try:
            if os.path.exists(self.REPO_BASE_DIR):
                active_workspaces = len([d for d in os.listdir(self.REPO_BASE_DIR)
                                        if os.path.isdir(os.path.join(self.REPO_BASE_DIR, d))])
                stats['active_workspaces'] = active_workspaces
        except OSError:
            stats['active_workspaces'] = 0

        return stats
