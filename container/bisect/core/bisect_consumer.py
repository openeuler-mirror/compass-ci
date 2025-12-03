#!/usr/bin/env python3


import sys
import os
import re
import time
import hashlib
import shutil
import traceback
import json

from datetime import datetime
from typing import Dict, Any, Optional, List

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger, StructuredLogger
from bisect_utils import extract_repo_name_from_url
from errid_intelligence import ErridIntelligence
from notification_writer import NotificationWriter

sys.path.append((os.environ['LKP_SRC']) + '/programs/bisect-py/')
from manticore_simple import ManticoreClient
from py_bisect import GitBisect

class BisectConsumer:
    """处理bisect任务的消费者"""

    def __init__(self, client: ManticoreClient, config: Dict):
        self.client = client
        self.config = config
        self.errid_intelligence = ErridIntelligence()
        self.notification_writer = NotificationWriter(
            notification_dir=config.get('notification_dir', '/result/bisect/notifications')
        )
        logger.debug("BisectConsumer initialized with ErridIntelligence and NotificationWriter")
    
    def process_single_task(self, task: Dict) -> Dict:
        """处理单个bisect任务"""
        try:
            task_id = int(task['id'])
            task_result_root = self._generate_task_path(self.config, task)
            
            # Debug log for result_root
            logger.debug(f"Generated task_result_root: {task_result_root} | task_id: {task_id}")
            
            if not task_result_root:
                logger.error(f"Failed to generate task_result_root | task_id: {task_id}")
                return {'status': 'failed', 'error': 'Failed to generate result_root', 'id': task_id, 'bad_job_id': task.get('bad_job_id', 'N/A')}
            
            # Use atomic operation to update task status, avoid race conditions
            current_time = int(time.time())
            update_query = f"""
                UPDATE bisect
                SET bisect_status = 'processing', updated_at = {current_time}
                WHERE id = {task_id} AND bisect_status = 'wait'
            """
            
            # Execute atomic update
            update_result = self.client.sql_raw(update_query)
            
            # Check if update succeeded (returns affected rows)
            if not update_result or update_result[0]['error'] != '':
                logger.warning(f"跳过任务 | ID: {task_id} | 状态已变更或不存在")
                return {'status': 'skipped', 'id': task_id, 'error': 'Task status changed or not exists'}
            
            logger.info(f"开始处理任务 | ID: {task_id}")

            # 查找并标记相似任务为pending_verification
            try:
                marked_count = self._find_and_mark_similar_tasks(task, task_id)
                if marked_count > 0:
                    logger.info(f"Marked {marked_count} similar tasks as pending_verification for task {task_id}")
            except Exception as e:
                logger.warning(f"Failed to mark similar tasks for task {task_id}: {str(e)}")

            # Prepare task data
            logger.debug(f"Step 1: Preparing task data | ID: {task_id}")
            task['bisect_result_root'] = task_result_root

            # Get shared repository
            logger.debug(f"Step 2: Getting git_url | ID: {task_id}")
            repo_url = task.get("git_url")
            if not repo_url:
                logger.error("任务缺少仓库URL")
                return {'status': 'failed', 'error': 'Missing git_url', 'id': task_id, 'bad_job_id': task.get('bad_job_id', 'N/A')}

            logger.debug(f"Step 3: Extracting good_commit from j field | ID: {task_id}")
            # Extract good_commit from j field BEFORE validation
            # This ensures validated_data contains good_commit from the start
            j_field = task.get('j') or {}
            if isinstance(j_field, str):
                try:
                    j_field = json.loads(j_field) if j_field else {}
                except:
                    j_field = {}
            elif not isinstance(j_field, dict):
                j_field = {}

            if j_field.get('good_commit'):
                task['good_commit'] = j_field['good_commit']
                logger.info(f"Extracted good_commit from j field: {j_field['good_commit']}")

            logger.debug(f"Step 4: Validating task data | ID: {task_id}")
            # Validate task data
            validated_data = self._validate_task_data(task)
            if 'error' in validated_data:
                return validated_data

            logger.debug(f"Step 5: Checking task type | ID: {task_id}")
            # Check task type
            task_type_result = self._check_task_type(task)
            if 'error' in task_type_result:
                return task_type_result

            # Execute bisect with context manager to ensure repo release
            # 使用 context manager 确保仓库总是被释放，即使在异常或进程崩溃时
            with self.repo_manager.get_repo_context(
                task['id'],
                task['bad_job_id'],
                repo_url
            ) as (repo_dir, job_dir):
                logger.info(f"使用共享仓库 | 路径: {repo_dir}")

                # Execute GitBisect
                gb = GitBisect()
                result = gb.find_first_bad_commit(validated_data, repo_dir=repo_dir)

                # Handle results (不需要手动释放仓库)
                return self._handle_bisect_result_no_release(result, task, task_id)
            
        except Exception as e:
            error_msg = f"Task {task.get('id', 'unknown_id')} failed: {str(e)}"
            logger.error(error_msg)

            # 更新数据库状态为失败
            task_id = task.get('id')
            if task_id:
                try:
                    # 生成 bisect_result_root，即使在异常情况下也要设置
                    bisect_result_root = task.get('bisect_result_root')
                    if not bisect_result_root:
                        try:
                            bisect_result_root = self._generate_task_path(self.config, task)
                            logger.info(f"为异常任务生成 bisect_result_root: {bisect_result_root}")
                        except Exception as path_e:
                            logger.error(f"生成异常任务路径失败: {str(path_e)}")
                            bisect_result_root = ""

                    fail_doc = {
                        "bisect_status": "failed",
                        "last_error": error_msg,
                        "bisect_result_root": bisect_result_root,
                        "updated_at": int(time.time())
                    }
                    self.client.update("bisect", task_id, fail_doc)
                    logger.info(f"已更新异常任务状态为failed | ID: {task_id}")
                except Exception as update_e:
                    logger.error(f"更新异常任务状态失败: {str(update_e)}")

            return {'id': task.get('id', 'unknown_id'), 'status': 'failed', 'error': error_msg, 'bad_job_id': task.get('bad_job_id', 'N/A')}

    def _calculate_confidence_from_git_verification(
        self, git_verification: Dict, boundary_verification: Dict, task_id: int
    ) -> str:
        """
        基于 git verification 结果计算置信度

        Args:
            git_verification: git 验证结果（包含 verified, confidence (0.0/0.5/1.0), file_analysis 等）
            boundary_verification: 边界验证信息
            task_id: 任务 ID

        Returns:
            'high', 'medium', 'low'
        """
        try:
            # 策略1: 如果有 git_verification.confidence，直接映射
            if git_verification and 'confidence' in git_verification:
                confidence_score = git_verification.get('confidence', 0.0)
                need_human_judgment = git_verification.get('need_human_judgment', False)
                verified = git_verification.get('verified', False)

                # 直接映射：1.0 -> high, 0.5 -> medium, 0.0 -> low
                if confidence_score >= 1.0:
                    confidence = 'high'
                elif confidence_score >= 0.5:
                    confidence = 'medium'
                else:
                    confidence = 'low'

                logger.info(
                    f"使用 git_verification 置信度 | task_id: {task_id} | "
                    f"score: {confidence_score} | level: {confidence} | "
                    f"verified: {verified} | need_human_judgment: {need_human_judgment}"
                )
                return confidence

            # 策略2: 检查是否通过 boundary verification
            verification_passed = boundary_verification.get('verification_passed', False)
            if verification_passed:
                logger.info(
                    f"边界验证通过，无 git verification | task_id: {task_id} | "
                    f"confidence: medium (fallback)"
                )
                return 'medium'

            # 策略3: 默认 low
            logger.warning(
                f"无验证数据 | task_id: {task_id} | confidence: low (default)"
            )
            return 'low'

        except Exception as e:
            logger.error(f"计算置信度失败 | task_id: {task_id} | error: {str(e)}")
            return 'low'

    def _find_and_mark_similar_tasks(self, current_task: Dict, task_id: int) -> int:
        """
        查找相似任务并标记为pending_verification

        Args:
            current_task: 当前正在处理的任务
            task_id: 当前任务ID

        Returns:
            标记的任务数量
        """
        try:
            error_id = current_task.get('error_id', '')
            if not error_id:
                logger.debug(f"Task {task_id} has no error_id, skipping similar task search")
                return 0

            # 提取错误签名
            error_signature = self.errid_intelligence.extract_coarse_signature(error_id)
            if not error_signature:
                logger.debug(f"Failed to extract signature from error_id: {error_id}")
                return 0

            logger.info(f"Finding similar tasks | task_id: {task_id} | signature: {error_signature}")

            # 查询具有相同签名的wait状态任务
            # 使用SQL查询以提高性能
            query = f"""
                SELECT id, error_id, bad_job_id
                FROM bisect
                WHERE bisect_status = 'wait'
                  AND error_id != ''
                  AND id != {task_id}
                LIMIT 1000
            """

            candidates = self.client.sql_select(query)
            if not candidates:
                logger.debug(f"No candidate tasks found for clustering")
                return 0

            # 客户端过滤：匹配相同签名的任务
            similar_tasks = []
            for candidate in candidates:
                candidate_error_id = candidate.get('error_id', '')
                if not candidate_error_id:
                    continue

                candidate_signature = self.errid_intelligence.extract_coarse_signature(candidate_error_id)
                if candidate_signature == error_signature:
                    similar_tasks.append(candidate)

            if not similar_tasks:
                logger.debug(f"No similar tasks found with signature: {error_signature}")
                return 0

            logger.info(f"Found {len(similar_tasks)} similar tasks with signature: {error_signature}")

            # 批量标记为pending_verification
            marked_count = 0
            current_time = int(time.time())

            for similar_task in similar_tasks:
                try:
                    similar_task_id = similar_task['id']

                    # 再次确认任务状态为 wait（避免竞态条件）
                    current_status = similar_task.get('bisect_status')
                    if current_status != 'wait':
                        logger.debug(f"Skip task {similar_task_id}: status is {current_status}, not 'wait'")
                        continue

                    # 读取现有j字段并合并（保留现有数据）
                    existing_j = similar_task.get('j') or {}
                    if isinstance(existing_j, str):
                        try:
                            existing_j = json.loads(existing_j) if existing_j else {}
                        except:
                            existing_j = {}
                    elif not isinstance(existing_j, dict):
                        existing_j = {}

                    # 合并新数据到现有j字段
                    updated_j = {
                        **existing_j,  # 保留现有数据
                        "related_task_id": str(task_id),
                        "error_signature": error_signature,
                        "original_error_id": similar_task.get("error_id", ""),
                        "clustering_timestamp": current_time,
                        "clustered_by": "bisect_consumer"
                    }

                    # 使用 HTTP JSON 接口更新（完全避免 SQL 转义问题）
                    update_doc = {
                        "doc": {
                            "bisect_status": "pending_verification",
                            "updated_at": current_time,
                            "j": updated_j  # 直接传递字典对象，ManticoreClient 自动处理 JSON 序列化
                        }
                    }

                    result = self.client.update("bisect", similar_task_id, update_doc)
                    if result:
                        marked_count += 1
                        logger.debug(f"Marked task {similar_task_id} as pending_verification, related to {task_id}")

                except Exception as e:
                    logger.error(f"Failed to mark task {similar_task.get('id')} as pending_verification: {str(e)}")
                    continue

            if marked_count > 0:
                logger.info(f"Marked {marked_count} similar tasks as pending_verification | main_task: {task_id}")

            return marked_count

        except Exception as e:
            logger.error(f"Error finding similar tasks for task {task_id}: {str(e)}")
            logger.error(traceback.format_exc())
            return 0

    def _promote_pending_verification_tasks(self, task_id: int) -> int:
        """
        将与当前任务关联的pending_verification任务提升为verifying状态

        Args:
            task_id: 当前成功完成的任务ID

        Returns:
            提升的任务数量
        """
        try:
            logger.info(f"Promoting pending_verification tasks for successful task {task_id}")

            # 查询所有与当前任务关联的pending_verification任务
            # 使用SQL查询j字段
            query = f"""
                SELECT id, j
                FROM bisect
                WHERE bisect_status = 'pending_verification'
                LIMIT 1000
            """

            pending_tasks = self.client.sql_select(query)
            if not pending_tasks:
                logger.debug(f"No pending_verification tasks found")
                return 0

            # 客户端过滤：找到related_task_id匹配的任务
            related_tasks = []
            for task in pending_tasks:
                try:
                    j_field = task.get('j') or '{}'
                    if isinstance(j_field, str):
                        j_data = json.loads(j_field) if j_field else {}
                    elif isinstance(j_field, dict):
                        j_data = j_field
                    else:
                        j_data = {}

                    related_id = j_data.get('related_task_id')
                    if related_id and str(related_id) == str(task_id):
                        related_tasks.append(task)
                except Exception as e:
                    logger.warning(f"Failed to parse j field for task {task.get('id')}: {str(e)}")
                    continue

            if not related_tasks:
                logger.debug(f"No pending_verification tasks related to task {task_id}")
                return 0

            logger.info(f"Found {len(related_tasks)} pending_verification tasks related to task {task_id}")

            # 收集所有需要提升的任务ID
            task_ids_to_promote = [task['id'] for task in related_tasks]

            if not task_ids_to_promote:
                logger.debug(f"No tasks to promote for task {task_id}")
                return 0

            # 批量提升为verifying（单次UPDATE查询）
            current_time = int(time.time())
            ids_str = ','.join(map(str, task_ids_to_promote))

            batch_update_query = f"""
                UPDATE bisect
                SET bisect_status = 'verifying',
                    updated_at = {current_time}
                WHERE id IN ({ids_str}) AND bisect_status = 'pending_verification'
            """

            try:
                result = self.client.sql_raw(batch_update_query)
                if result and result[0].get('error') == '':
                    # ManticoreSearch返回更新的行数
                    promoted_count = len(task_ids_to_promote)
                    logger.info(f"Batch promoted {promoted_count} tasks from pending_verification to verifying")
                    return promoted_count
                else:
                    error_msg = result[0].get('error', 'Unknown error') if result else 'No result'
                    logger.error(f"Batch promotion failed: {error_msg}")
                    return 0
            except Exception as e:
                logger.error(f"Failed to batch promote tasks: {str(e)}")
                return 0

        except Exception as e:
            logger.error(f"Error promoting pending_verification tasks for task {task_id}: {str(e)}")
            logger.error(traceback.format_exc())
            return 0

    def _validate_task_data(self, task: Dict) -> Dict:
        """验证任务数据"""
        validated = task.copy()
        
        # Ensure j field is not null
        if 'j' in validated and validated['j'] is None:
            logger.warning(f"清理无效的 j 字段 | 任务ID={validated.get('id')}")
            validated['j'] = {}
        
        # Ensure basic required fields exist
        if 'bad_job_id' not in validated:
            return {'error': 'Missing bad_job_id', 'id': validated.get('id', 'unknown_id')}
        
        if not validated['bad_job_id'] or not str(validated['bad_job_id']).strip():
            return {'error': 'Invalid bad_job_id', 'id': validated.get('id', 'unknown_id')}
        
        # Check task type: must have either error_id or bisect_metric
        has_error_id = validated.get("error_id") and str(validated["error_id"]).strip()
        has_metrics = validated.get("bisect_metric") is not None and str(validated["bisect_metric"]).strip() != ""
        
        # Truncate long strings for logging to avoid spam
        log_error_id = (validated.get('error_id', 'None')[:100] + '...') if len(validated.get('error_id', '')) > 100 else validated.get('error_id', 'None')
        log_bisect_metric = (str(validated.get('bisect_metric', 'None'))[:100] + '...') if len(str(validated.get('bisect_metric', ''))) > 100 else validated.get('bisect_metric', 'None')

        logger.debug(f"任务类型检查 | Task ID: {validated.get('id')} | error_id: '{log_error_id}' | bisect_metric: '{log_bisect_metric}' | has_error_id: {has_error_id} | has_metrics: {has_metrics}")
        
        if not has_error_id and not has_metrics:
            return {'error': 'Missing task type: must specify either error_id or bisect_metric', 'id': validated.get('id', 'unknown_id')}
            
        if has_error_id and has_metrics:
            return {'error': 'Task type conflict: cannot specify both error_id and bisect_metric', 'id': validated.get('id', 'unknown_id')}
        
        # 清理空字符串字段
        cleaned_data = {}
        for key, value in validated.items():
            if isinstance(value, str) and value.strip() == '':
                continue  # 跳过空字符串字段
            cleaned_data[key] = value
        
        return cleaned_data
    
    def _check_task_type(self, task: Dict) -> Dict:
        """检查任务类型"""
        has_error_id = task.get("error_id") and str(task["error_id"]).strip()
        has_metrics = task.get("bisect_metric") is not None and str(task["bisect_metric"]).strip() != ""
        
        if not has_error_id and not has_metrics:
            return {'error': 'Missing task type: must specify either error_id or bisect_metric'}
        
        if has_error_id and has_metrics:
            return {'error': 'Task type conflict: cannot specify both error_id and bisect_metric'}
        
        return {'task_type': 'error' if has_error_id else 'performance'}
    
    def _get_repo_dir(self, task_id: str, bad_job_id: str, repo_url: str):
        """获取仓库目录"""
        # Need to inject repo_manager from external
        if not hasattr(self, 'repo_manager'):
            sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
            from repo_manager import SharedRepoManager
            self.repo_manager = SharedRepoManager()

        return self.repo_manager.get_repo_dir(task_id, bad_job_id, repo_url)
    
    def _handle_bisect_result_no_release(self, result: Any, task: Dict, task_id: int) -> Dict:
        """处理bisect结果（不释放仓库，因为使用context manager）"""
        if result and isinstance(result, dict) and result.get('first_bad_commit'):
            # Success handling logic
            # 新流程：Git bisect 已包含验证，直接标记验证完成
            current_time = int(time.time())

            # 提取 boundary_verification 信息（防御性：确保是字典）
            boundary_verification = result.get('boundary_verification') or {}

            # 诊断日志：检查 boundary_verification 是否为空
            if not boundary_verification:
                logger.warning(f"任务 {task_id} 的 boundary_verification 为空，无法获取 introduced_errids")
                logger.warning(f"result keys: {list(result.keys()) if isinstance(result, dict) else 'not_dict'}")

            introduced_errids = boundary_verification.get('introduced_errids', []) or []

            # 提取 git verification 结果（包含置信度信息）
            git_verification = boundary_verification.get('git_verification') or {}
            parent_job_id = boundary_verification.get('parent_job_id')
            parent_commit = boundary_verification.get('parent_commit')
            head_commit = boundary_verification.get('head_commit')
            verification_status = boundary_verification.get('status')
            verification_passed = boundary_verification.get('verification_passed', False)

            # Extract errid_log_context (error log messages)
            errid_log_context = boundary_verification.get('errid_log_context', {}) or {}
            if errid_log_context:
                logger.info(f"提取 errid_log_context | task_id: {task_id} | errids: {len(errid_log_context)} 个有日志上下文")
            else:
                logger.info(f"无 errid_log_context | task_id: {task_id}")

            # Extract HEAD check results (py_bisect already completed HEAD detection)
            head_check = boundary_verification.get('head_check') or {}
            head_check_status = head_check.get('status')
            head_check_job_id = boundary_verification.get('head_job_id')
            head_regressed_errids = head_check.get('regressed_errids', []) or []

            if head_check:
                logger.info(f"提取 HEAD 检测结果 | task_id: {task_id} | status: {head_check_status} | regressed: {len(head_regressed_errids)}")
            else:
                logger.info(f"无 HEAD 检测结果 | task_id: {task_id} | py_bisect 可能未运行 HEAD 检测")

            # 如果没有 introduced_errids 但有 parent_job_id，尝试重新计算
            if not introduced_errids and parent_job_id:
                try:
                    bad_job_id = task.get('bad_job_id')
                    logger.warning(f"boundary_verification 中没有 introduced_errids，尝试重新计算 | parent: {parent_job_id} | bad: {bad_job_id}")
                    from verification_consumer import create_verification_consumer
                    vc = create_verification_consumer(self.config)
                    introduced_errids = vc.calculate_errid_diff(str(parent_job_id), str(bad_job_id))
                    logger.info(f"重新计算得到 {len(introduced_errids)} 个 introduced_errids")
                except Exception as calc_err:
                    logger.error(f"重新计算 introduced_errids 失败: {str(calc_err)}")
                    introduced_errids = []

            logger.info(f"Bisect成功 | task_id: {task_id} | introduced_errids: {len(introduced_errids)} 个 | boundary_verification: {'有' if boundary_verification else '无'}")
            if introduced_errids and len(introduced_errids) <= 5:
                logger.info(f"  Sample introduced_errids: {introduced_errids[:5]}")
            elif not introduced_errids:
                logger.warning(f"任务 {task_id} 没有 introduced_errids | parent_job: {parent_job_id} | parent_commit: {parent_commit}")

            # 提取其他有用信息（防御性：确保是字典）
            bisect_range = result.get('bisect_range') or {}
            verification_info = result.get('verification') or {}

            # 计算置信度（基于 git verification 结果）
            confidence = self._calculate_confidence_from_git_verification(
                git_verification, boundary_verification, task_id
            )

            success_doc = {
                "bisect_status": "success",
                "first_bad_commit": result.get('first_bad_commit', '') or '',  # 纯 SHA
                "first_bad_id": result.get('first_bad_id', '') or '',
                "first_result_root": result.get('bad_result_root', '') or '',
                "bisect_result_root": task.get('bisect_result_root', '') or '',
                "start_time": result.get('start_time', 0) or 0,
                "end_time": result.get('end_time', 0) or 0,
                "last_error": "",  # 清空之前的错误信息
                "updated_at": current_time,
                "j": {
                    # 验证状态
                    "verification_status": "verified",
                    "verification_method": "integrated_bisect",
                    "validation_status": "completed",
                    "verified": True,
                    "confidence": confidence,  # 动态计算的置信度
                    "skip_success_validation": True,

                    # first_bad_commit 相关字段
                    "first_bad_commit_subject": result.get('first_bad_commit_subject', ''),
                    # change_point: SHA + subject，用于显示
                    "change_point": result.get('change_point', ''),

                    # boundary_verification 完整信息（来自 py_bisect）
                    "boundary_verification": boundary_verification,

                    # 快捷访问字段（避免深层嵌套，从 boundary_verification 中提取）
                    "introduced_errids": introduced_errids,
                    "introduced_errids_count": len(introduced_errids),
                    "errid_log_context": errid_log_context,
                    "parent_job_id": parent_job_id,
                    "parent_commit": parent_commit,
                    "verification_passed": verification_passed,

                    # HEAD 检测结果（从 py_bisect 提取，与 head_validator 使用相同字段名）
                    "head_check_status": head_check_status,
                    "head_check_commit": head_commit,
                    "head_check_job_id": head_check_job_id,
                    "head_check_at": current_time if head_check_status else None,
                    "head_check_source": "py_bisect" if head_check_status else None,
                    "regressed_errids": head_regressed_errids,
                    "head_check_completed": bool(head_check_status),

                    # bisect_range 信息（完整对象）
                    "bisect_range": bisect_range,
                    # 快捷访问字段
                    "start_commit": bisect_range.get('start_commit'),
                    "end_commit": bisect_range.get('end_commit'),

                    # verification 信息（来自 py_bisect，完整对象）
                    "verification_info": verification_info,
                    # 快捷访问字段
                    "verification_reason": verification_info.get('reason'),
                    "verification_confidence": verification_info.get('confidence'),

                    # job reuse 统计（来自 py_bisect）
                    "job_request_count": result.get('job_request_count', 0),
                    "job_reused_count": result.get('job_reused_count', 0),
                    "job_reused_rate": result.get('job_reused_rate', 0.0)
                }
            }

            self.client.update("bisect", task_id, success_doc)

            # 生成通知和记录
            try:
                from bisect_utils import write_regression_record
                write_regression_record(
                    task_id=task_id,
                    bad_job_id=task.get('bad_job_id'),
                    first_bad_commit=result.get('first_bad_commit'),
                    git_url=task.get('git_url'),
                    error_id=task.get('error_id'),
                    bisect_metric=task.get('bisect_metric')
                )
            except Exception as e:
                logger.warning(f"写入regression记录失败: {str(e)}")

            # 报告生成逻辑：
            # - 如果 py_bisect 已完成 HEAD 检测（head_check_completed = true），立即生成报告
            # - 如果未完成 HEAD 检测，报告生成延迟到 head_validator 完成后
            if head_check_status:
                # py_bisect 已完成 HEAD 检测，立即生成报告
                logger.info(f"py_bisect 已完成 HEAD 检测 | task_id: {task_id} | 立即生成报告")
                try:
                    # 重新查询任务以获取更新后的完整信息（包含 j 字段）
                    updated_tasks = self.client.sql_select(f"SELECT * FROM bisect WHERE id = {task_id}")
                    if updated_tasks:
                        updated_task = updated_tasks[0]

                        # 获取 job 信息用于报告
                        bad_job_id = task.get('bad_job_id')
                        job_info = None
                        if bad_job_id:
                            try:
                                job_query = f"SELECT * FROM jobs WHERE id = {int(bad_job_id)} LIMIT 1"
                                job_results = self.client.sql_select(job_query)
                                if job_results and len(job_results) > 0:
                                    job_info = job_results[0]
                            except Exception as e:
                                logger.warning(f"获取 job 信息失败 | job_id: {bad_job_id} | error: {str(e)}")

                        # 生成报告
                        report_path = self.notification_writer.write_bisect_success_report(
                            updated_task,
                            job_info=job_info,
                            introduced_errids=introduced_errids
                        )
                        if report_path:
                            logger.info(f"Bisect 成功报告已生成 | task_id: {task_id} | path: {report_path}")
                        else:
                            logger.warning(f"Bisect 成功报告生成失败 | task_id: {task_id}")
                    else:
                        logger.warning(f"无法获取更新后的任务信息 | task_id: {task_id}")
                except Exception as e:
                    logger.error(f"生成 bisect 成功报告异常 | task_id: {task_id} | error: {str(e)}")
                    logger.error(traceback.format_exc())
            else:
                # py_bisect 未完成 HEAD 检测，报告生成延迟到 head_validator
                logger.info(f"py_bisect 未完成 HEAD 检测 | task_id: {task_id} | 报告生成延迟到 head_validator")

            # 提升相关的pending_verification任务为verifying
            try:
                promoted_count = self._promote_pending_verification_tasks(task_id)
                if promoted_count > 0:
                    logger.info(f"Promoted {promoted_count} pending_verification tasks to verifying for successful task {task_id}")
            except Exception as e:
                logger.warning(f"Failed to promote pending_verification tasks for task {task_id}: {str(e)}")

            logger.info(f"任务执行成功（含集成验证） | ID: {task_id} | first_bad_commit: {result.get('first_bad_commit')}")
            return {
                'status': 'success',
                'id': task_id,
                'first_bad_commit': result.get('first_bad_commit', '')
            }

        else:
            # Failure handling logic
            error_msg = "Bisect execution failed"
            if isinstance(result, dict) and result.get('error'):
                error_msg = result.get('error')

            # 确保失败任务也有正确的 bisect_result_root
            bisect_result_root = task.get('bisect_result_root', '')
            if not bisect_result_root:
                # 如果没有设置，重新生成
                bisect_result_root = self._generate_task_path(self.config, task)
                logger.info(f"为失败任务重新生成 bisect_result_root: {bisect_result_root}")

            fail_doc = {
                "bisect_status": "failed",
                "last_error": error_msg,
                "bisect_result_root": bisect_result_root,
                "updated_at": int(time.time())
            }

            self.client.update("bisect", task_id, fail_doc)
            logger.error(f"任务执行失败 | ID: {task_id} | 原因: {error_msg}")
            return {'status': 'failed', 'error': error_msg, 'id': task_id}

    def _handle_bisect_result(self, result: Any, task: Dict, task_id: int, repo_dir: str, job_dir: str) -> Dict:
        """处理bisect结果"""
        if result and isinstance(result, dict) and result.get('first_bad_commit'):
            # Success handling logic
            success_doc = {
                "bisect_status": "success",
                "first_bad_commit": result.get('first_bad_commit', '') or '',
                "first_bad_id": result.get('first_bad_id', '') or '',
                "first_result_root": result.get('bad_result_root', '') or '',
                "bisect_result_root": task.get('bisect_result_root', '') or '',
                "start_time": result.get('start_time', 0) or 0,
                "end_time": result.get('end_time', 0) or 0,
                "last_error": "",  # 清空之前的错误信息
                "updated_at": int(time.time())
            }
            
            # Release repository back to pool
            try:
                if os.path.exists(repo_dir):
                    self.repo_manager.release_repo_dir(repo_dir)
                    logger.info(f"成功任务仓库已释放回池 | repo_dir: {repo_dir}")
            except Exception as e:
                logger.error(f"释放成功任务仓库时出错，回退到删除: {str(e)}")
                try:
                    if os.path.exists(job_dir):
                        shutil.rmtree(job_dir)
                except:
                    pass
            
            self.client.update("bisect", task_id, success_doc)
            logger.info(f"任务执行成功 | ID: {task_id}")
            return {
                'status': 'success',
                'id': task_id,
                'first_bad_commit': result.get('first_bad_commit', '')
            }
            
        else:
            # Failure handling logic
            error_msg = "Bisect execution failed"
            if isinstance(result, dict) and result.get('error'):
                error_msg = result.get('error')
            
            # 确保失败任务也有正确的 bisect_result_root
            bisect_result_root = task.get('bisect_result_root', '')
            if not bisect_result_root:
                # 如果没有设置，重新生成
                bisect_result_root = self._generate_task_path(self.config, task)
                logger.info(f"为失败任务重新生成 bisect_result_root: {bisect_result_root}")

            fail_doc = {
                "bisect_status": "failed",
                "last_error": error_msg,
                "bisect_result_root": bisect_result_root,
                "updated_at": int(time.time())
            }
            
            # Release repository back to pool on failure
            try:
                if os.path.exists(repo_dir):
                    self.repo_manager.release_repo_dir(repo_dir)
                    logger.info(f"失败任务仓库已释放回池 | repo_dir: {repo_dir}")
            except Exception as e:
                logger.error(f"释放失败任务仓库时出错，回退到删除: {str(e)}")
                try:
                    if os.path.exists(job_dir):
                        shutil.rmtree(job_dir)
                except:
                    pass
            
            self.client.update("bisect", task_id, fail_doc)
            logger.error(f"任务执行失败 | ID: {task_id} | 原因: {error_msg}")
            return {'status': 'failed', 'error': error_msg, 'id': task_id}
    
    @staticmethod
    def _generate_task_path(config: Dict, task: Dict) -> str:
        """生成任务路径"""
        repo_name = extract_repo_name_from_url(task.get('git_url'))

        # 为不同类型的任务生成合适的路径标识符
        task_identifier = ""
        if task.get('error_id'):
            task_identifier = hashlib.md5(task['error_id'].encode()).hexdigest()[:8]
        elif task.get('bisect_metric'):
            task_identifier = hashlib.md5(task['bisect_metric'].encode()).hexdigest()[:8]
        else:
            task_identifier = "unknown"

        result_base = os.environ.get('RESULT_DIR', '/result/bisect')
        path = os.path.join(
            result_base,
            'results',
            repo_name,
            datetime.now().strftime("%Y-%m-%d"),
            str(task['bad_job_id']),
            task_identifier,
            str(task['id'])
        )
        os.makedirs(path, exist_ok=True, mode=0o755)
        return os.path.abspath(path)



# Simplified consumer factory function
def create_consumer(config: Dict) -> BisectConsumer:
    """创建消费者实例"""
    client = ManticoreClient(config.get('manticore_host', 'http://localhost:9308'))
    return BisectConsumer(client, config)
