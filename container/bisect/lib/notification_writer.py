#!/usr/bin/env python3
"""
通知内容写入器
将各种通知内容保存到文件系统
"""

import os
import re
import json
import time
import subprocess
from datetime import datetime
from typing import Dict, List, Optional
from pathlib import Path


class NotificationWriter:
    """通知内容写入器"""
    
    def __init__(self, notification_dir: Optional[str] = None):
        """
        初始化通知写入器
        
        Args:
            notification_dir: 通知目录路径，默认为 $CCI_SRC/container/bisect/notifications
        """
        if notification_dir is None:
            base_dir = os.environ.get('CCI_SRC', '/srv/cci')
            notification_dir = os.path.join(base_dir, 'container/bisect/notifications')
        
        self.notification_dir = Path(notification_dir)
        self._ensure_directories()
    
    def _ensure_directories(self):
        """确保通知目录结构存在"""
        # 创建主目录和子目录
        subdirs = [
            'head_regression',      # HEAD 回归告警
            'head_fixed',           # HEAD 修复报告（好消息！）
            'verification_failed',  # 验证失败通知
            'validation_timeout',   # 验证超时通知
            'head_check_timeout',   # HEAD 检测超时
            'bisect_success',       # bisect 成功报告（kernel test robot风格）
            'sent'                  # 已发送的通知（归档）
        ]

        for subdir in subdirs:
            (self.notification_dir / subdir).mkdir(parents=True, exist_ok=True)
    
    def write_head_regression_alert(self, task: Dict, regressed_errids: List[str]) -> str:
        """
        写入 HEAD 回归告警
        
        Args:
            task: 任务信息
            regressed_errids: 回归的 errid 列表
        
        Returns:
            生成的通知文件路径
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())
        filename = f"regression_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'head_regression' / filename
        
        # 解析 j 字段
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            j_field = json.loads(j_field)
        
        # 生成通知内容
        content = self._format_head_regression_alert(task, j_field, regressed_errids)
        
        # 写入文件
        filepath.write_text(content, encoding='utf-8')
        
        # 同时保存 JSON 格式（方便程序处理）
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': 'head_regression',
            'task_id': task_id,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'task': {
                'id': task_id,
                'error_id': task.get('error_id'),
                'first_bad_commit': task.get('first_bad_commit'),
                'git_url': task.get('git_url'),
                'head_commit': j_field.get('head_check_commit'),
                'head_job_id': j_field.get('head_check_job_id'),
            },
            'regressed_errids': regressed_errids,
            'regressed_count': len(regressed_errids),
            'total_errids': len(j_field.get('introduced_errids', [])),
            'severity': self._calculate_severity(len(regressed_errids))
        }
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)

    def write_head_fixed_report(self, task: Dict, introduced_errids: List[str]) -> str:
        """
        写入 HEAD 修复报告（好消息！）

        Args:
            task: 任务信息
            introduced_errids: 原始引入的 errid 列表

        Returns:
            生成的通知文件路径
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())
        filename = f"fixed_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'head_fixed' / filename

        # 解析 j 字段
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            j_field = json.loads(j_field)

        # 生成通知内容
        content = self._format_head_fixed_report(task, j_field, introduced_errids)

        # 写入文件
        filepath.write_text(content, encoding='utf-8')

        # 同时保存 JSON 格式
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': 'head_fixed',
            'task_id': task_id,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'task': {
                'id': task_id,
                'error_id': task.get('error_id'),
                'first_bad_commit': task.get('first_bad_commit'),
                'git_url': task.get('git_url'),
                'head_commit': j_field.get('head_check_commit'),
                'head_job_id': j_field.get('head_check_job_id'),
            },
            'introduced_errids': introduced_errids,
            'introduced_count': len(introduced_errids),
            'status': 'fixed',
            'priority': 'info'  # 好消息，优先级较低
        }
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)

    def write_verification_failed_alert(
        self,
        task_id: int,
        error_id: str,
        first_bad_commit: str,
        git_url: str,
        failure_reason: str,
        extra_info: Dict = None
    ) -> str:
        """
        写入验证失败通知

        Args:
            task_id: 任务ID
            error_id: 错误ID
            first_bad_commit: First bad commit
            git_url: Git仓库URL
            failure_reason: 失败原因
            extra_info: 额外信息（可选）

        Returns:
            生成的通知文件路径
        """
        timestamp = int(time.time())
        filename = f"verification_failed_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'verification_failed' / filename

        # 生成通知内容
        content = self._format_verification_failed_alert(
            task_id, error_id, first_bad_commit, git_url, failure_reason, extra_info or {}
        )

        # 写入文件
        filepath.write_text(content, encoding='utf-8')

        # JSON 格式
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': 'verification_failed',
            'task_id': task_id,
            'error_id': error_id,
            'first_bad_commit': first_bad_commit,
            'git_url': git_url,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'failure_reason': failure_reason,
            'requires_action': '边界条件不满足' in failure_reason,
            'unverifiable': extra_info.get('unverifiable', False) if extra_info else False,
            'requires_manual_review': extra_info.get('requires_manual_review', False) if extra_info else False,
            'extra_info': extra_info or {}
        }
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)
    
    def write_timeout_alert(
        self,
        task_id: int,
        error_id: str,
        timeout_type: str,
        reason: str,
        elapsed_time: int = None
    ) -> str:
        """
        写入超时告警

        Args:
            task_id: 任务ID
            error_id: 错误ID
            timeout_type: 超时类型（validation 或 head_check）
            reason: 超时原因描述
            elapsed_time: 超时时长（秒），可选

        Returns:
            生成的通知文件路径
        """
        timestamp = int(time.time())
        subdir = 'validation_timeout' if timeout_type == 'validation' else 'head_check_timeout'
        filename = f"timeout_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / subdir / filename

        # 生成通知内容
        content = self._format_timeout_alert(task_id, error_id, timeout_type, reason, elapsed_time)

        # 写入文件
        filepath.write_text(content, encoding='utf-8')

        # JSON 格式
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': f'{timeout_type}_timeout',
            'task_id': task_id,
            'error_id': error_id,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'timeout_type': timeout_type,
            'reason': reason
        }
        if elapsed_time is not None:
            json_data['elapsed_time'] = elapsed_time
            json_data['elapsed_hours'] = round(elapsed_time / 3600, 2)
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)

    def write_bisect_success_report(
        self,
        task: Dict,
        job_info: Dict = None,
        introduced_errids: List[str] = None
    ) -> str:
        """
        写入 bisect 成功报告（kernel test robot 风格）

        Args:
            task: 任务信息字典，包含:
                - id: 任务ID
                - error_id: 错误ID
                - first_bad_commit: First bad commit hash
                - git_url: Git 仓库URL
                - bad_job_id: Bad job ID
                - confidence_level: 置信度（high/medium/low/unknown）
                - j: JSON字段（可能包含额外信息）
            job_info: 作业信息字典（可选），包含:
                - suite: 测试套件名称
                - testcase: 测试用例名称
                - arch: 架构
                - config: 配置名称
                - compiler: 编译器信息
                - head_commit: HEAD commit hash
            introduced_errids: 引入的错误ID列表（可选）

        Returns:
            生成的报告文件路径
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())

        # 获取 first_bad_commit 短 SHA (前12位)
        first_bad_commit = task.get('first_bad_commit', '')
        commit_short = first_bad_commit[:12] if first_bad_commit else 'unknown'

        # 从error_id提取并清理符号，用于文件名
        error_id = task.get('error_id', '')
        if error_id:
            # 取最后一段（通常是最具体的错误信息）
            error_id_part = error_id.split('.')[-1]
            # 移除所有非字母数字字符，将特殊字符替换为连字符
            # 先替换特殊字符为连字符，再去掉连续的连字符
            sanitized_errid = re.sub(r'[^a-zA-Z0-9]+', '-', error_id_part)
            # 去掉首尾的连字符
            sanitized_errid = sanitized_errid.strip('-')
            # 限制长度
            sanitized_errid = sanitized_errid[:50] if sanitized_errid else 'unknown'
        else:
            sanitized_errid = 'unknown'

        # 获取置信度，决定子目录
        confidence_level = task.get('confidence_level', 'unknown')

        # 根据置信度选择子目录
        if confidence_level in ('high', 'unknown'):
            subdir = 'bisect_success'
        elif confidence_level == 'medium':
            subdir = 'bisect_success_medium'
        else:  # low
            subdir = 'bisect_success_suspicious'

        # 文件名格式: bisect_success_{commit}_{task_id}_{sanitized_errid}.txt
        filename = f"bisect_success_{commit_short}_{task_id}_{sanitized_errid}.txt"
        filepath = self.notification_dir / subdir / filename

        # 解析 j 字段
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except json.JSONDecodeError:
                j_field = {}

        # 生成报告内容（包含置信度警告）
        content = self._format_bisect_success_report(
            task, job_info or {}, j_field, introduced_errids or [], confidence_level
        )

        # 写入文件
        filepath.write_text(content, encoding='utf-8')

        # 同时保存 JSON 格式（方便程序处理）
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': 'bisect_success',
            'task_id': task_id,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'confidence_level': confidence_level,  # 新增
            'task': {
                'id': task_id,
                'error_id': task.get('error_id'),
                'first_bad_commit': task.get('first_bad_commit'),
                'git_url': task.get('git_url'),
                'bad_job_id': task.get('bad_job_id'),
            },
            'job_info': job_info or {},
            'introduced_errids': introduced_errids or [],
            'introduced_count': len(introduced_errids) if introduced_errids else 0,
            'file_check_result': j_field.get('file_check_result'),  # 新增
        }
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)

    def _format_head_regression_alert(self, task: Dict, j_field: Dict, regressed_errids: List[str]) -> str:
        """格式化 HEAD 回归告警内容"""
        task_id = task.get('id', 'unknown')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        error_id = task.get('error_id', 'N/A')
        
        head_commit = j_field.get('head_check_commit', 'N/A')
        head_job_id = j_field.get('head_check_job_id', 'N/A')
        introduced_errids = j_field.get('introduced_errids', [])
        
        # 截断长错误ID用于显示
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id
        
        content = f"""
================================================================================
【HEAD 回归告警】
================================================================================

告警时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
告警级别: {self._calculate_severity(len(regressed_errids))}

--------------------------------------------------------------------------------
任务信息
--------------------------------------------------------------------------------
任务ID:           {task_id}
错误ID:           {error_id_display}
First Bad Commit: {first_bad_commit[:12]}
Git 仓库:         {git_url}

--------------------------------------------------------------------------------
回归详情
--------------------------------------------------------------------------------
HEAD Commit:      {head_commit[:12] if head_commit != 'N/A' else 'N/A'}
HEAD Job ID:      {head_job_id}
引入的错误总数:   {len(introduced_errids)}
回归的错误数:     {len(regressed_errids)}
回归率:           {len(regressed_errids) / len(introduced_errids) * 100:.1f}%

--------------------------------------------------------------------------------
回归的错误列表（前10个）
--------------------------------------------------------------------------------
"""
        for i, errid in enumerate(regressed_errids[:10], 1):
            errid_display = errid[:80] + '...' if len(errid) > 80 else errid
            content += f"{i}. {errid_display}\n"
        
        if len(regressed_errids) > 10:
            content += f"\n... 还有 {len(regressed_errids) - 10} 个错误\n"
        
        content += f"""
--------------------------------------------------------------------------------
建议操作
--------------------------------------------------------------------------------
1. 查看 HEAD 测试作业详情: 
   curl "http://api:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_id={head_job_id}"

2. 查看任务详情:
   SELECT * FROM bisect WHERE id = {task_id};

3. 对比 first_bad_commit 和 HEAD 的差异:
   git diff {first_bad_commit[:12]}..{head_commit[:12] if head_commit != 'N/A' else 'HEAD'}

4. 确认是否需要修复或提交 bug 报告

================================================================================
"""
        return content

    def _format_head_fixed_report(self, task: Dict, j_field: Dict, introduced_errids: List[str]) -> str:
        """格式化 HEAD 修复报告内容（好消息！）"""
        task_id = task.get('id', 'unknown')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        error_id = task.get('error_id', 'N/A')

        head_commit = j_field.get('head_check_commit', 'N/A')
        head_job_id = j_field.get('head_check_job_id', 'N/A')

        # 截断长错误ID用于显示
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        content = f"""
================================================================================
【HEAD 修复报告】✅
================================================================================

报告时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
优先级:   INFO（好消息！）

--------------------------------------------------------------------------------
任务信息
--------------------------------------------------------------------------------
任务ID:           {task_id}
错误ID:           {error_id_display}
First Bad Commit: {first_bad_commit[:12]}
Git 仓库:         {git_url}

--------------------------------------------------------------------------------
修复详情
--------------------------------------------------------------------------------
HEAD Commit:      {head_commit[:12] if head_commit != 'N/A' else 'N/A'}
HEAD Job ID:      {head_job_id}
原引入的错误数:   {len(introduced_errids)}
HEAD 状态:        ✅ 所有错误已修复！

--------------------------------------------------------------------------------
原引入的错误列表（前10个）
--------------------------------------------------------------------------------
"""
        for i, errid in enumerate(introduced_errids[:10], 1):
            errid_display = errid[:80] + '...' if len(errid) > 80 else errid
            content += f"{i}. {errid_display}\n"

        if len(introduced_errids) > 10:
            content += f"\n... 还有 {len(introduced_errids) - 10} 个错误\n"

        content += f"""
--------------------------------------------------------------------------------
建议操作
--------------------------------------------------------------------------------
1. 可以关闭相关的 bug 跟踪记录

2. 查看修复的提交范围:
   git log {first_bad_commit[:12]}..{head_commit[:12] if head_commit != 'N/A' else 'HEAD'}

3. 确认修复提交:
   git log --grep="fix" --oneline {first_bad_commit[:12]}..{head_commit[:12] if head_commit != 'N/A' else 'HEAD'}

================================================================================
"""
        return content

    def _format_verification_failed_alert(
        self,
        task_id: int,
        error_id: str,
        first_bad_commit: str,
        git_url: str,
        failure_reason: str,
        extra_info: Dict
    ) -> str:
        """格式化验证失败告警内容"""
        # 截断长错误ID用于显示
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        unverifiable = extra_info.get('unverifiable', False)
        requires_manual_review = extra_info.get('requires_manual_review', False)

        content = f"""
================================================================================
【验证失败通知】{'【需要人工审核】' if requires_manual_review else ''}
================================================================================

通知时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
{'告警级别: 高 (HIGH) - 不可验证任务' if unverifiable else '告警级别: 中 (MEDIUM)'}

--------------------------------------------------------------------------------
任务信息
--------------------------------------------------------------------------------
任务ID:           {task_id}
错误ID:           {error_id_display}
First Bad Commit: {first_bad_commit}
Git 仓库:         {git_url}

--------------------------------------------------------------------------------
失败详情
--------------------------------------------------------------------------------
失败原因: {failure_reason}
"""
        if extra_info.get('verification_details'):
            content += "\n验证详情:\n"
            for key, value in extra_info['verification_details'].items():
                content += f"  {key}: {value}\n"

        content += f"""
--------------------------------------------------------------------------------
建议操作
--------------------------------------------------------------------------------
"""
        if '边界条件不满足' in failure_reason or unverifiable:
            content += f"""
【重要】此任务已标记为不可验证，需要人工审核

原因分析:
  - 边界条件不满足通常表示 parent commit 和 candidate commit 都是 good
  - 这可能是 flaky test（不稳定测试）或 bisect 错误导致
  - 环境差异也可能导致此问题

建议操作:
1. 人工审核该 bisect 结果的准确性
2. 查询任务详情:
   SELECT * FROM bisect WHERE id = {task_id};
3. 检查测试用例是否为 flaky test
4. 考虑调整测试环境或重新配置测试参数
5. 如果确认是误报，可以手动更新任务状态

【不建议】自动重新 bisect（可能得到相同结果，浪费资源）
"""
        else:
            content += f"""
1. 检查系统日志排查错误原因
2. 如果是临时错误（超时、网络问题等），可以考虑重试验证
3. 查询任务详情:
   SELECT * FROM bisect WHERE id = {task_id};
4. 检查是否需要调整验证参数或环境配置
"""

        content += "\n================================================================================\n"
        return content
    
    def _format_timeout_alert(
        self,
        task_id: int,
        error_id: str,
        timeout_type: str,
        reason: str,
        elapsed_time: int = None
    ) -> str:
        """格式化超时告警内容"""
        timeout_name = "验证作业" if timeout_type == "validation" else "HEAD 检测"

        # 截断长错误ID用于显示
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        content = f"""
================================================================================
【{timeout_name}超时告警】
================================================================================

告警时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
告警级别: 中等 (MEDIUM)

--------------------------------------------------------------------------------
任务信息
--------------------------------------------------------------------------------
任务ID:      {task_id}
错误ID:      {error_id_display}
超时类型:    {timeout_name}
超时原因:    {reason}
"""
        if elapsed_time is not None:
            timeout_hours = elapsed_time / 3600
            content += f"超时时长:    {elapsed_time} 秒 ({timeout_hours:.2f} 小时)\n"

        content += f"""
--------------------------------------------------------------------------------
建议操作
--------------------------------------------------------------------------------
1. 检查作业是否仍在运行（可能卡住）
2. 查询任务详情:
   SELECT * FROM bisect WHERE id = {task_id};
3. 检查系统资源使用情况
4. 考虑调整超时阈值或优化测试流程
5. 如需重试，可手动重置任务状态

================================================================================
"""
        return content

    def _format_bisect_success_report(
        self,
        task: Dict,
        job_info: Dict,
        j_field: Dict,
        introduced_errids: List[str],
        confidence_level: str = 'unknown'
    ) -> str:
        """格式化 bisect 成功报告内容（kernel test robot 风格）"""
        task_id = task.get('id', 'unknown')
        error_id = task.get('error_id', 'N/A')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        bad_job_id = task.get('bad_job_id', 'N/A')

        # 从 git_url 提取 tree 信息
        tree_url = git_url
        # 尝试提取分支名（如果 j_field 中有）
        branch = j_field.get('branch', 'master')

        # 从 job_info 获取详细信息
        suite = job_info.get('suite', 'N/A')
        testcase = job_info.get('testcase', 'N/A')
        arch = job_info.get('arch', 'N/A')
        config = job_info.get('config', 'N/A')
        compiler = job_info.get('compiler', 'N/A')

        # HEAD 信息：优先从 j_field 获取（py_bisect 或 head_validator 提供）
        head_check_commit = j_field.get('head_check_commit') or job_info.get('head_commit') or 'N/A'
        head_check_status = j_field.get('head_check_status') or 'N/A'

        # 格式化 HEAD 显示：commit (status)
        if head_check_commit and head_check_commit != 'N/A' and head_check_status != 'N/A':
            head_display = f"{head_check_commit[:12]} ({head_check_status})"
        elif head_check_commit and head_check_commit != 'N/A':
            head_display = head_check_commit[:12]
        else:
            head_display = 'N/A'

        # 组合显示：优先使用 j.change_point，否则组合 first_bad_commit + subject
        change_point = j_field.get('change_point') or ''
        if change_point:
            commit_display = change_point
        else:
            # 兼容旧数据：从 j.first_bad_commit_subject 组合
            commit_subject = j_field.get('first_bad_commit_subject') or ''
            if commit_subject:
                commit_display = f"{first_bad_commit} {commit_subject}"
            else:
                commit_display = first_bad_commit if first_bad_commit else 'N/A'

        # 截断长错误ID用于显示
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        # 生成日期时间
        report_time = datetime.now().strftime('%Y%m%d')

        content = f"""tree:   {tree_url} {branch}
head:   {head_display}
commit: {commit_display}
"""

        # 如果有配置信息，添加配置行
        if config != 'N/A':
            content += f"config: {config}\n"

        # 如果有编译器信息，添加编译器行
        if compiler != 'N/A':
            content += f"compiler: {compiler}\n"

        content += f"""
================================================================================
Bisect Report - {report_time}
================================================================================

Task ID:     {task_id}
Bad Job ID:  {bad_job_id}

Test Suite:  {suite}
Test Case:   {testcase}
Architecture: {arch}

Error ID:
{error_id_display}

First Bad Commit:
{commit_display}

"""

        # 如果置信度不高，添加警告部分
        if confidence_level != 'high' and confidence_level != 'unknown':
            file_check_result = j_field.get('file_check_result', {})
            mention_ratio = file_check_result.get('mention_ratio', 0)
            mentioned_files = file_check_result.get('mentioned_files', [])
            total_files = file_check_result.get('total_files', 0)

            content += """
================================================================================
CONFIDENCE WARNING
================================================================================

"""
            content += f"Confidence Level: {confidence_level.upper()}\n"
            content += f"Changed Files: {total_files}\n"
            content += f"Mentioned Files: {len(mentioned_files)}\n"
            content += f"Mention Ratio: {mention_ratio:.1%}\n"
            content += "\n"

            if confidence_level == 'low':
                content += """WARNING: Very low file correlation detected!
The files changed by this commit are rarely mentioned in the error output.

This could indicate:
  - False positive bisect result
  - Flaky test
  - Indirect/cascade failure

Manual review is STRONGLY RECOMMENDED.
"""
            else:  # medium
                content += """Note: Moderate file correlation detected.
Manual review is recommended to verify the bisect result.
"""

            if mentioned_files:
                content += f"\nMentioned files ({len(mentioned_files)}):\n"
                for f in mentioned_files[:10]:
                    content += f"  {f}\n"
                if len(mentioned_files) > 10:
                    content += f"  ... and {len(mentioned_files) - 10} more\n"

            content += "\n"

        # 如果有引入的错误列表，显示它们（过滤掉 .msg 后缀的项）
        if introduced_errids:
            # 过滤掉 .msg 后缀的 errid
            filtered_errids = [e for e in introduced_errids if not e.endswith('.msg')]

            # 获取 errid_log_context（如果有的话）
            errid_log_context = j_field.get('errid_log_context', {})

            if filtered_errids:
                content += f"""Introduced Error IDs ({len(filtered_errids)} total):
--------------------------------------------------------------------------------
"""
                # 显示前10个错误ID
                for i, errid in enumerate(filtered_errids[:10], 1):
                    # 如果有 log context，显示日志原文；否则显示 errid
                    if errid in errid_log_context:
                        log_msg = errid_log_context[errid]
                        # 截断过长的日志（保留前200个字符）
                        if len(log_msg) > 200:
                            log_display = log_msg[:200] + '...'
                        else:
                            log_display = log_msg
                        # 去除 errid 前缀，只保留简短的标识
                        errid_short = errid.split('.')[-1] if '.' in errid else errid
                        content += f"{i}. {errid_short}: {log_display}\n"
                    else:
                        # 没有 log context，显示 errid
                        errid_display = errid[:80] + '...' if len(errid) > 80 else errid
                        content += f"{i}. {errid_display}\n"

                if len(filtered_errids) > 10:
                    content += f"\n... and {len(filtered_errids) - 10} more error(s)\n"

                content += "\n"

        content += f"""================================================================================
Repository Information
================================================================================
Git URL:     {git_url}
Branch:      {branch}
Bad Commit:  {commit_display}
HEAD:        {head_display}

================================================================================
Notes
================================================================================
This bisect was performed automatically by the bisect system.

To reproduce the issue:
1. Clone the repository:
   git clone {git_url}

2. Checkout the first bad commit:
   git checkout {first_bad_commit}

3. Build and test with the configuration used in the original test

For more details about this bisect task:
   Task ID: {task_id}
   Bad Job ID: {bad_job_id}

================================================================================
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
================================================================================
"""
        return content

    def _calculate_severity(self, regressed_count: int) -> str:
        """计算告警级别"""
        if regressed_count >= 5:
            return "严重 (CRITICAL)"
        elif regressed_count >= 3:
            return "重要 (HIGH)"
        elif regressed_count >= 1:
            return "中等 (MEDIUM)"
        else:
            return "低 (LOW)"
    
    def mark_as_sent(self, filepath: str):
        """将通知标记为已发送（移动到 sent 目录）"""
        source = Path(filepath)
        if not source.exists():
            return
        
        # 移动到 sent 目录
        dest = self.notification_dir / 'sent' / source.name
        source.rename(dest)
        
        # 同时移动 JSON 文件
        json_source = source.with_suffix('.json')
        if json_source.exists():
            json_dest = dest.with_suffix('.json')
            json_source.rename(json_dest)
    
    def get_pending_notifications(self, notification_type: Optional[str] = None) -> List[str]:
        """
        获取待发送的通知列表
        
        Args:
            notification_type: 通知类型（head_regression, verification_failed, 等）
                              None 表示所有类型
        
        Returns:
            通知文件路径列表
        """
        notifications = []
        
        if notification_type:
            search_dirs = [self.notification_dir / notification_type]
        else:
            search_dirs = [
                self.notification_dir / 'head_regression',
                self.notification_dir / 'head_fixed',
                self.notification_dir / 'verification_failed',
                self.notification_dir / 'validation_timeout',
                self.notification_dir / 'head_check_timeout',
                self.notification_dir / 'bisect_success'
            ]
        
        for search_dir in search_dirs:
            if search_dir.exists():
                notifications.extend([str(f) for f in search_dir.glob('*.txt')])
        
        return sorted(notifications)


if __name__ == '__main__':
    # 测试代码
    writer = NotificationWriter('/tmp/bisect_notifications_test')

    print("="*80)
    print("测试 1: HEAD 回归告警")
    print("="*80)
    test_task = {
        'id': 12345,
        'error_id': 'test.error.panic.kernel',
        'first_bad_commit': 'abc123def456',
        'git_url': 'https://github.com/torvalds/linux.git',
        'j': {
            'head_check_commit': 'fed456abc123',
            'head_check_job_id': '67890',
            'introduced_errids': ['error1', 'error2', 'error3']
        }
    }

    filepath = writer.write_head_regression_alert(test_task, ['error1', 'error2'])
    print(f"生成告警文件: {filepath}")
    print(f"\n内容预览:")
    print(Path(filepath).read_text()[:500])

    print("\n" + "="*80)
    print("测试 2: Bisect 成功报告 (kernel test robot 风格)")
    print("="*80)

    # 测试 bisect 成功报告
    bisect_task = {
        'id': 4658439017074994670,
        'error_id': 'arch_numa.make_node_reclaim_distance_adjustment_always_available.ld_error',
        'first_bad_commit': '5e5d40e65cb55e4699c9879674a004f246606a8d',
        'git_url': 'https://gitee.com/openeuler/kernel.git',
        'bad_job_id': '202511151309',
        'j': {
            'branch': 'OLK-6.6'
        }
    }

    job_info = {
        'suite': 'build',
        'testcase': 'makepkg',
        'arch': 'arm64',
        'config': 'arm64-randconfig-002-20251115',
        'compiler': 'clang version 18.1.8',
        'head_commit': '5f56814d65eaa85e3277534a309f4e7b4f095412'
    }

    introduced_errids = [
        'arch_numa.make_node_reclaim_distance_adjustment_always_available.ld_error',
        'mm.make_node_reclaim_distance_adjustment_always_available.warning',
    ]

    filepath = writer.write_bisect_success_report(bisect_task, job_info, introduced_errids)
    print(f"生成成功报告文件: {filepath}")
    print(f"\n完整内容:")
    print(Path(filepath).read_text())

    print("\n" + "="*80)
    print("测试 3: 查看生成的 JSON 文件")
    print("="*80)
    json_filepath = Path(filepath).with_suffix('.json')
    if json_filepath.exists():
        print(f"JSON 文件: {json_filepath}")
        print(json.dumps(json.loads(json_filepath.read_text()), indent=2))
