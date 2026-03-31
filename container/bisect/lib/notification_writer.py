#!/usr/bin/env python3
"""

file
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
    """"""
    
    def __init__(self, notification_dir: Optional[str] = None):
        """
        initialize
        
        Args:
            notification_dir: , default $CCI_SRC/container/bisect/notifications
        """
        if notification_dir is None:
            base_dir = os.environ.get('CCI_SRC', '/srv/cci')
            notification_dir = os.path.join(base_dir, 'container/bisect/notifications')
        
        self.notification_dir = Path(notification_dir)
        self._ensure_directories()
    
    def _ensure_directories(self):
        """"""
        # create
        subdirs = [
            'head_regression',      # HEAD regression
            'head_fixed',           # HEAD fixed(！)
            'verification_failed',  # verification failed
            'validation_timeout',   # verifytimeout
            'head_check_timeout',   # HEAD timeout
            'bisect_success',       # bisect success(kernel test robot)
            'sent'                  # ()
        ]

        for subdir in subdirs:
            (self.notification_dir / subdir).mkdir(parents=True, exist_ok=True)
    
    def write_head_regression_alert(self, task: Dict, regressed_errids: List[str]) -> str:
        """
         HEAD regression
        
        Args:
            task: task
            regressed_errids: regression errid list
        
        Returns:
            file
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())
        filename = f"regression_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'head_regression' / filename
        
        #  j 
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            j_field = json.loads(j_field)
        
        # 
        content = self._format_head_regression_alert(task, j_field, regressed_errids)
        
        # file
        filepath.write_text(content, encoding='utf-8')
        
        #  JSON ()
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
         HEAD fixed(！)

        Args:
            task: task
            introduced_errids:  errid list

        Returns:
            file
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())
        filename = f"fixed_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'head_fixed' / filename

        #  j 
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            j_field = json.loads(j_field)

        # 
        content = self._format_head_fixed_report(task, j_field, introduced_errids)

        # file
        filepath.write_text(content, encoding='utf-8')

        #  JSON 
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
            'priority': 'info'  # , 
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
        verification failed

        Args:
            task_id: taskID
            error_id: errorID
            first_bad_commit: First bad commit
            git_url: GitrepoURL
            failure_reason: failedreason
            extra_info: ()

        Returns:
            file
        """
        timestamp = int(time.time())
        filename = f"verification_failed_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / 'verification_failed' / filename

        # 
        content = self._format_verification_failed_alert(
            task_id, error_id, first_bad_commit, git_url, failure_reason, extra_info or {}
        )

        # file
        filepath.write_text(content, encoding='utf-8')

        # JSON 
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
            'requires_action': 'conditions' in failure_reason,
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
        timeout

        Args:
            task_id: taskID
            error_id: errorID
            timeout_type: timeout(validation  head_check)
            reason: timeoutreason
            elapsed_time: timeout(), 

        Returns:
            file
        """
        timestamp = int(time.time())
        subdir = 'validation_timeout' if timeout_type == 'validation' else 'head_check_timeout'
        filename = f"timeout_{task_id}_{timestamp}.txt"
        filepath = self.notification_dir / subdir / filename

        # 
        content = self._format_timeout_alert(task_id, error_id, timeout_type, reason, elapsed_time)

        # file
        filepath.write_text(content, encoding='utf-8')

        # JSON 
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
         bisect success(kernel test robot )

        Args:
            task: taskdict, :
                - id: taskID
                - error_id: errorID
                - first_bad_commit: First bad commit hash
                - git_url: Git repoURL
                - bad_job_id: Bad job ID
                - confidence_level: (high/medium/low/unknown)
                - j: JSON()
            job_info: jobdict(), :
                - suite: test
                - testcase: test
                - arch: 
                - config: config
                - compiler: 
                - head_commit: HEAD commit hash
            introduced_errids: errorIDlist()

        Returns:
            file
        """
        task_id = task.get('id', 'unknown')
        timestamp = int(time.time())

        # get first_bad_commit  SHA (12)
        first_bad_commit = task.get('first_bad_commit', '')
        commit_short = first_bad_commit[:12] if first_bad_commit else 'unknown'

        # error_id, file
        error_id = task.get('error_id', '')
        if error_id:
            # (error)
            error_id_part = error_id.split('.')[-1]
            # , 
            # , 
            sanitized_errid = re.sub(r'[^a-zA-Z0-9]+', '-', error_id_part)
            # 
            sanitized_errid = sanitized_errid.strip('-')
            # 
            sanitized_errid = sanitized_errid[:50] if sanitized_errid else 'unknown'
        else:
            sanitized_errid = 'unknown'

        # get, 
        confidence_level = task.get('confidence_level', 'unknown')

        # 
        if confidence_level in ('high', 'unknown'):
            subdir = 'bisect_success'
        elif confidence_level == 'medium':
            subdir = 'bisect_success_medium'
        else:  # low
            subdir = 'bisect_success_suspicious'

        # file: bisect_success_{commit}_{task_id}_{sanitized_errid}.txt
        filename = f"bisect_success_{commit_short}_{task_id}_{sanitized_errid}.txt"
        filepath = self.notification_dir / subdir / filename

        #  j 
        j_field = task.get('j', {})
        if isinstance(j_field, str):
            try:
                j_field = json.loads(j_field) if j_field else {}
            except json.JSONDecodeError:
                j_field = {}

        # (warning)
        content = self._format_bisect_success_report(
            task, job_info or {}, j_field, introduced_errids or [], confidence_level
        )

        # file
        filepath.write_text(content, encoding='utf-8')

        #  JSON ()
        json_filepath = filepath.with_suffix('.json')
        json_data = {
            'type': 'bisect_success',
            'task_id': task_id,
            'timestamp': timestamp,
            'datetime': datetime.fromtimestamp(timestamp).isoformat(),
            'confidence_level': confidence_level,  # 
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
            'file_check_result': j_field.get('file_check_result'),  # 
        }
        json_filepath.write_text(json.dumps(json_data, indent=2, ensure_ascii=False), encoding='utf-8')

        return str(filepath)

    def _format_head_regression_alert(self, task: Dict, j_field: Dict, regressed_errids: List[str]) -> str:
        """ HEAD regression"""
        task_id = task.get('id', 'unknown')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        error_id = task.get('error_id', 'N/A')
        
        head_commit = j_field.get('head_check_commit', 'N/A')
        head_job_id = j_field.get('head_check_job_id', 'N/A')
        introduced_errids = j_field.get('introduced_errids', [])
        
        # errorID
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id
        
        content = f"""
================================================================================
【HEAD regression】
================================================================================

: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
: {self._calculate_severity(len(regressed_errids))}

--------------------------------------------------------------------------------
task
--------------------------------------------------------------------------------
taskID:           {task_id}
errorID:           {error_id_display}
First Bad Commit: {first_bad_commit[:12]}
Git repo:         {git_url}

--------------------------------------------------------------------------------
regression
--------------------------------------------------------------------------------
HEAD Commit:      {head_commit[:12] if head_commit != 'N/A' else 'N/A'}
HEAD Job ID:      {head_job_id}
error:   {len(introduced_errids)}
regressionerror:     {len(regressed_errids)}
regression:           {len(regressed_errids) / len(introduced_errids) * 100:.1f}%

--------------------------------------------------------------------------------
regressionerrorlist(10)
--------------------------------------------------------------------------------
"""
        for i, errid in enumerate(regressed_errids[:10], 1):
            errid_display = errid[:80] + '...' if len(errid) > 80 else errid
            content += f"{i}. {errid_display}\n"
        
        if len(regressed_errids) > 10:
            content += f"\n...  {len(regressed_errids) - 10} error\n"
        
        content += f"""
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
1.  HEAD testjob: 
   curl "http://api:3000/~lkp/cgi-bin/lkp-jobfile-append-var?job_id={head_job_id}"

2. task:
   SELECT * FROM bisect WHERE id = {task_id};

3.  first_bad_commit  HEAD :
   git diff {first_bad_commit[:12]}..{head_commit[:12] if head_commit != 'N/A' else 'HEAD'}

4. fixedsubmit bug 

================================================================================
"""
        return content

    def _format_head_fixed_report(self, task: Dict, j_field: Dict, introduced_errids: List[str]) -> str:
        """ HEAD fixed(！)"""
        task_id = task.get('id', 'unknown')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        error_id = task.get('error_id', 'N/A')

        head_commit = j_field.get('head_check_commit', 'N/A')
        head_job_id = j_field.get('head_check_job_id', 'N/A')

        # errorID
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        content = f"""
================================================================================
【HEAD fixed】✅
================================================================================

: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
:   INFO(！)

--------------------------------------------------------------------------------
task
--------------------------------------------------------------------------------
taskID:           {task_id}
errorID:           {error_id_display}
First Bad Commit: {first_bad_commit[:12]}
Git repo:         {git_url}

--------------------------------------------------------------------------------
fixed
--------------------------------------------------------------------------------
HEAD Commit:      {head_commit[:12] if head_commit != 'N/A' else 'N/A'}
HEAD Job ID:      {head_job_id}
error:   {len(introduced_errids)}
HEAD status:        ✅ errorfixed！

--------------------------------------------------------------------------------
errorlist(10)
--------------------------------------------------------------------------------
"""
        for i, errid in enumerate(introduced_errids[:10], 1):
            errid_display = errid[:80] + '...' if len(errid) > 80 else errid
            content += f"{i}. {errid_display}\n"

        if len(introduced_errids) > 10:
            content += f"\n...  {len(introduced_errids) - 10} error\n"

        content += f"""
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
1. related bug 

2. fixedsubmit:
   git log {first_bad_commit[:12]}..{head_commit[:12] if head_commit != 'N/A' else 'HEAD'}

3. fixedsubmit:
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
        """verification failed"""
        # errorID
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        unverifiable = extra_info.get('unverifiable', False)
        requires_manual_review = extra_info.get('requires_manual_review', False)

        content = f"""
================================================================================
【verification failed】{'【】' if requires_manual_review else ''}
================================================================================

: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
{':  (HIGH) - verification task' if unverifiable else ':  (MEDIUM)'}

--------------------------------------------------------------------------------
task
--------------------------------------------------------------------------------
taskID:           {task_id}
errorID:           {error_id_display}
First Bad Commit: {first_bad_commit}
Git repo:         {git_url}

--------------------------------------------------------------------------------
failed
--------------------------------------------------------------------------------
failedreason: {failure_reason}
"""
        if extra_info.get('verification_details'):
            content += "\nverify:\n"
            for key, value in extra_info['verification_details'].items():
                content += f"  {key}: {value}\n"

        content += f"""
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
"""
        if 'conditions' in failure_reason or unverifiable:
            content += f"""
【】task verification, 

reason:
  - conditions parent commit  candidate commit  good
  -  flaky test(test) bisect error
  - 

:
1.  bisect 
2. querytask:
   SELECT * FROM bisect WHERE id = {task_id};
3. checktest flaky test
4. testconfigtest
5. , taskstatus

【】 bisect(, )
"""
        else:
            content += f"""
1. checklogerrorreason
2. error(timeout、), verify
3. querytask:
   SELECT * FROM bisect WHERE id = {task_id};
4. checkverifyconfig
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
        """timeout"""
        timeout_name = "verification job" if timeout_type == "validation" else "HEAD "

        # errorID
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        content = f"""
================================================================================
【{timeout_name}timeout】
================================================================================

: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
:  (MEDIUM)

--------------------------------------------------------------------------------
task
--------------------------------------------------------------------------------
taskID:      {task_id}
errorID:      {error_id_display}
timeout:    {timeout_name}
timeoutreason:    {reason}
"""
        if elapsed_time is not None:
            timeout_hours = elapsed_time / 3600
            content += f"timeout:    {elapsed_time}  ({timeout_hours:.2f} )\n"

        content += f"""
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
1. checkjob()
2. querytask:
   SELECT * FROM bisect WHERE id = {task_id};
3. check
4. timeouttest
5. , resettaskstatus

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
        """ bisect success(kernel test robot )"""
        task_id = task.get('id', 'unknown')
        error_id = task.get('error_id', 'N/A')
        first_bad_commit = task.get('first_bad_commit', 'N/A')
        git_url = task.get('git_url', 'N/A')
        bad_job_id = task.get('bad_job_id', 'N/A')

        #  git_url  tree 
        tree_url = git_url
        # ( j_field )
        branch = j_field.get('branch', 'master')

        #  job_info get
        suite = job_info.get('suite', 'N/A')
        testcase = job_info.get('testcase', 'N/A')
        arch = job_info.get('arch', 'N/A')
        config = job_info.get('config', 'N/A')
        compiler = job_info.get('compiler', 'N/A')

        # HEAD :  j_field get(py_bisect  head_validator )
        head_check_commit = j_field.get('head_check_commit') or job_info.get('head_commit') or 'N/A'
        head_check_status = j_field.get('head_check_status') or 'N/A'

        #  HEAD : commit (status)
        if head_check_commit and head_check_commit != 'N/A' and head_check_status != 'N/A':
            head_display = f"{head_check_commit[:12]} ({head_check_status})"
        elif head_check_commit and head_check_commit != 'N/A':
            head_display = head_check_commit[:12]
        else:
            head_display = 'N/A'

        # :  j.change_point,  first_bad_commit + subject
        change_point = j_field.get('change_point') or ''
        if change_point:
            commit_display = change_point
        else:
            # :  j.first_bad_commit_subject 
            commit_subject = j_field.get('first_bad_commit_subject') or ''
            if commit_subject:
                commit_display = f"{first_bad_commit} {commit_subject}"
            else:
                commit_display = first_bad_commit if first_bad_commit else 'N/A'

        # errorID
        error_id_display = error_id[:100] + '...' if len(error_id) > 100 else error_id

        # 
        report_time = datetime.now().strftime('%Y%m%d')

        content = f"""tree:   {tree_url} {branch}
head:   {head_display}
commit: {commit_display}
"""

        # config, config
        if config != 'N/A':
            content += f"config: {config}\n"

        # , 
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

        # , warning
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

        # errorlist, ( .msg )
        if introduced_errids:
            #  .msg  errid
            filtered_errids = [e for e in introduced_errids if not e.endswith('.msg')]

            # get errid_log_context()
            errid_log_context = j_field.get('errid_log_context', {})

            if filtered_errids:
                content += f"""Introduced Error IDs ({len(filtered_errids)} total):
--------------------------------------------------------------------------------
"""
                # 10errorID
                for i, errid in enumerate(filtered_errids[:10], 1):
                    #  log context, log； errid
                    if errid in errid_log_context:
                        log_msg = errid_log_context[errid]
                        # log(200)
                        if len(log_msg) > 200:
                            log_display = log_msg[:200] + '...'
                        else:
                            log_display = log_msg
                        #  errid , 
                        errid_short = errid.split('.')[-1] if '.' in errid else errid
                        content += f"{i}. {errid_short}: {log_display}\n"
                    else:
                        #  log context,  errid
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
        """"""
        if regressed_count >= 5:
            return " (CRITICAL)"
        elif regressed_count >= 3:
            return " (HIGH)"
        elif regressed_count >= 1:
            return " (MEDIUM)"
        else:
            return " (LOW)"
    
    def mark_as_sent(self, filepath: str):
        """( sent )"""
        source = Path(filepath)
        if not source.exists():
            return
        
        #  sent 
        dest = self.notification_dir / 'sent' / source.name
        source.rename(dest)
        
        #  JSON file
        json_source = source.with_suffix('.json')
        if json_source.exists():
            json_dest = dest.with_suffix('.json')
            json_source.rename(json_dest)
    
    def get_pending_notifications(self, notification_type: Optional[str] = None) -> List[str]:
        """
        getlist
        
        Args:
            notification_type: (head_regression, verification_failed, )
                              None 
        
        Returns:
            filelist
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
    # test
    writer = NotificationWriter('/tmp/bisect_notifications_test')

    print("="*80)
    print("test 1: HEAD regression")
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
    print(f"file: {filepath}")
    print(f"\n:")
    print(Path(filepath).read_text()[:500])

    print("\n" + "="*80)
    print("test 2: Bisect success (kernel test robot )")
    print("="*80)

    # test bisect success
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
    print(f"successfile: {filepath}")
    print(f"\n:")
    print(Path(filepath).read_text())

    print("\n" + "="*80)
    print("test 3:  JSON file")
    print("="*80)
    json_filepath = Path(filepath).with_suffix('.json')
    if json_filepath.exists():
        print(f"JSON file: {json_filepath}")
        print(json.dumps(json.loads(json_filepath.read_text()), indent=2))
