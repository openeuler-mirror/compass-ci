#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
智能 Error ID 筛选机制

这个模块实现了多层智能筛选算法，用于从大量 errid 中选择最适合进行 bisect 的错误。
"""

import re
import os
import sys
import yaml
from pathlib import Path
from typing import List, Dict, Set, Tuple, Optional
from dataclasses import dataclass, field
from enum import Enum

sys.path.append((os.environ['CCI_SRC']) + '/container/bisect/lib')
from log_config import logger

class ErrorPriority(Enum):
    """错误优先级枚举"""
    CRITICAL = 100    # 严重错误，最优先
    HIGH = 80        # 高优先级
    MEDIUM = 60      # 中等优先级
    LOW = 40         # 低优先级
    IGNORE = 0       # 忽略

@dataclass
class ErrorAnalysis:
    """错误分析结果"""
    errid: str
    original_errid: str = ""  # 新增：保留原始error_id用于bisect匹配
    priority: int = 0
    reasons: List[str] = field(default_factory=list)
    flags: Dict[str, bool] = field(default_factory=dict)
    file_paths: List[str] = field(default_factory=list)
    error_type: str = ""

class ErridIntelligence:
    """智能 Error ID 筛选器"""

    def __init__(self, config_path: Optional[str] = None):
        """
        初始化智能筛选器

        Args:
            config_path: 配置文件路径，如果为None则使用默认路径
        """
        # 设置配置文件路径
        if config_path is None:
            config_path = os.path.join(
                os.environ['CCI_SRC'],
                'container/bisect/config/errid_filters.yaml'
            )

        self.config_path = config_path
        self.config_mtime = 0  # 配置文件修改时间（用于热重载）
        self.config = {}  # 存储配置内容

        # 加载配置
        self._load_config()

        logger.info(f"智能筛选器初始化完成 | 配置文件: {self.config_path}")
        logger.info(f"配置版本: {self.config.get('version', 'unknown')}")
        logger.info(f"环境黑名单规则: {len(self.environment_blacklist)} 条")
        logger.info(f"高价值白名单: {len(self.value_whitelist)} 条")
        logger.info(f"代码相关模式: {len(self.code_positive_patterns)} 条")
        logger.info(f"错误分类: {len(self.error_categories)} 个")

    def _load_config(self):
        """从YAML配置文件加载筛选规则"""
        try:
            config_file = Path(self.config_path)

            if not config_file.exists():
                logger.warning(f"配置文件不存在: {self.config_path}，使用默认配置")
                self._load_default_config()
                return

            # 检查文件修改时间
            current_mtime = config_file.stat().st_mtime
            if current_mtime == self.config_mtime and hasattr(self, 'file_path_patterns'):
                # 配置未修改且已加载，跳过
                return

            # 读取配置文件
            with open(config_file, 'r', encoding='utf-8') as f:
                self.config = yaml.safe_load(f)

            self.config_mtime = current_mtime

            # 1. 加载文件路径识别模式
            self.file_path_patterns = [
                item['pattern'] for item in self.config.get('file_path_patterns', [])
            ]

            # 2. 加载错误关键词
            self.error_keywords = self.config.get('error_keywords', {})

            # 3. 加载环境错误黑名单
            self.environment_blacklist = [
                item['pattern'] for item in self.config.get('environment_blacklist', [])
            ]

            # 4. 加载高价值白名单（包括优先级加成）
            self.value_whitelist_data = self.config.get('value_whitelist', [])
            self.value_whitelist = [item['pattern'] for item in self.value_whitelist_data]

            # 5. 加载代码相关积极信号
            self.code_positive_patterns_data = self.config.get('code_positive_patterns', [])
            self.code_positive_patterns = [item['pattern'] for item in self.code_positive_patterns_data]

            # 6. 加载错误分类
            self.error_categories = self.config.get('error_categories', {})

            # 7. 加载优先级评分规则
            self.priority_scoring = self.config.get('priority_scoring', {
                'has_file_path': 30,
                'critical_level': 40,
                'high_level': 25,
                'medium_level': 15,
                'code_related': 20,
                'appropriate_length': 10,
                'whitelist_match': 20
            })

            # 8. 加载长度评估规则
            self.length_eval = self.config.get('length_evaluation', {
                'min_length': 50,
                'max_length': 500,
                'optimal_min': 80,
                'optimal_max': 300
            })

            # 9. 加载默认参数
            self.default_params = self.config.get('default_parameters', {
                'max_count': 6,
                'min_priority': 10,
                'whitelist_boost': 20
            })

            # 10. 加载构建任务过滤规则
            self.build_task_filters = self.config.get('build_task_filters', {})
            if self.build_task_filters.get('enable_build_filtering', False):
                self.allowed_kernel_repos = [
                    item['pattern'] for item in self.build_task_filters.get('allowed_kernel_repos', [])
                ]
                logger.info(f"构建任务过滤已启用 | 允许的内核仓库: {len(self.allowed_kernel_repos)} 个")
            else:
                self.allowed_kernel_repos = []

            logger.info(f"配置文件加载成功 | 版本: {self.config.get('version', 'unknown')}")

        except Exception as e:
            logger.error(f"加载配置文件失败: {str(e)}")
            logger.warning("将使用默认配置")
            self._load_default_config()

    def _load_default_config(self):
        """加载默认配置（当配置文件不存在或加载失败时使用）"""
        logger.info("加载默认硬编码配置")

        # 文件路径正则表达式 - 增强版，支持更多格式
        self.file_path_patterns = [
            r'[\./\w-]+\.(?:h|c|cpp|py|rs|go|java|js):\d+:\d+',
            r'[\./\w-]+\.(?:h|c|cpp|py|rs|go|java|js):#:#:',
            r'\/[\w\.-/]+/[\w\.-]+\.\w+:\d+',
        ]

        # 错误关键词（按优先级排序）
        self.error_keywords = {
            'critical': ['error', 'Error', 'ERROR', 'fatal', 'FATAL', 'panic', 'PANIC'],
            'high': ['warning', 'Warning', 'WARNING', 'fail', 'failed', 'FAIL', 'FAILED'],
            'medium': ['warn', 'WARN', 'deprecated', 'DEPRECATED'],
        }

        # 环境错误黑名单（应该被过滤掉的）
        self.environment_blacklist = [
            r'No_such_file_or_directory',
            r'command_not_found',
            r'Permission_denied',
            r'Connection_refused',
            r'Network_is_unreachable',
            r'/usr/bin/env.*not.*found',
            r'ruby.*not.*found',
            r'python.*not.*found',
            r'bash.*not.*found',
            r'.*\.rpm.*not.*found',
            r'package.*not.*available',
            r'repository.*not.*found',
            r'Failure_while_creating_working_copy_of.*git_repo',
            r'ambiguous.*not_found_in_the_build_directory',
            r'detect_arch_by_readelf.*gpg-error',
            r'git_update_cache_failed',
            r'curl.*The.*requested.*URL.*returned.*error',
            r'The.*requested.*URL.*returned.*error',
            r'curl:\(\d+\)',
            r'File_already_exists_on_server',
            r'/srv/file-store/.*already_exists',
            r'has_stderr$',
            r'upload.*error',
            r'download.*error',
            r'network.*timeout',
            r'^stderr\.eid\.install-',  # 安装脚本错误
            r'install-m#',              # install 命令错误
            r'==>ERROR:A.failure.occurred.in.(build|prepare|package|check)\(\)',  # makepkg 构建流程错误
            r'==>WARNING:Skipping-',    # makepkg 流程警告
            r'^last_state\.eid\.exit_fail$',
            r'^last_state\.eid\.test\..*exit_code\.\d+$',
        ]

        # 代码相关的积极信号
        self.code_positive_patterns = [
            r'compile.*error',
            r'build.*error',
            r'link.*error',
            r'syntax.*error',
            r'parse.*error',
            r'type.*error',
            r'undefined.*reference',
            r'undeclared.*identifier',
            r'implicit.*declaration',
            r'conflicting.*types',
            r'__.*_overflow',
            r'fortify.*string',
        ]

        # 白名单：已知高价值的错误类型
        self.value_whitelist = [
            r'kernel.*panic',
            r'segmentation.*fault',
            r'stack.*overflow',
            r'buffer.*overflow',
            r'memory.*leak',
            r'null.*pointer',
            r'division.*by.*zero',
            r'__.*_overflow.*declared_with_attribute_error',
            r'detected_.*_beyond_size',
        ]

        # 默认评分规则
        self.priority_scoring = {
            'has_file_path': 30,
            'critical_level': 40,
            'high_level': 25,
            'medium_level': 15,
            'code_related': 20,
            'appropriate_length': 10,
            'whitelist_match': 20
        }

        # 默认长度评估
        self.length_eval = {
            'min_length': 50,
            'max_length': 500,
            'optimal_min': 80,
            'optimal_max': 300
        }

        # 默认参数
        self.default_params = {
            'max_count': 6,
            'min_priority': 40,  # 提高到40以确保任务质量
            'whitelist_boost': 20
        }

        # 错误分类（默认）
        self.error_categories = {}

    def reload_config_if_changed(self):
        """检查配置文件是否修改，如果修改则重新加载（热重载）"""
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                return False

            current_mtime = config_file.stat().st_mtime
            if current_mtime != self.config_mtime:
                logger.info("检测到配置文件修改，重新加载配置...")
                self._load_config()
                return True

            return False

        except Exception as e:
            logger.error(f"检查配置文件修改时出错: {str(e)}")
            return False

    def analyze_errid(self, errid: str) -> ErrorAnalysis:
        """分析单个 error ID，返回分析结果"""
        analysis = ErrorAnalysis(errid=errid, original_errid=errid)  # 保留原始完整字符串

        # 1. 环境错误检查（黑名单）
        if self._is_environment_error(errid):
            analysis.priority = ErrorPriority.IGNORE.value
            analysis.reasons.append("环境配置错误，不适合bisect")
            return analysis

        # 2. 高价值错误检查（白名单）
        if self._is_high_value_error(errid):
            analysis.priority = ErrorPriority.CRITICAL.value
            analysis.reasons.append("高价值错误类型")

        # 3. 文件路径检查
        file_paths = self._extract_file_paths(errid)
        if file_paths:
            analysis.file_paths = file_paths
            score_boost = self.priority_scoring.get('has_file_path', 30)
            analysis.priority += score_boost
            analysis.reasons.append(f"包含文件路径: {len(file_paths)}个")
            analysis.flags['has_file_path'] = True

        # 4. 错误级别检查
        error_level = self._detect_error_level(errid)
        if error_level == 'critical':
            score_boost = self.priority_scoring.get('critical_level', 40)
            analysis.priority += score_boost
            analysis.reasons.append("严重错误级别")
            analysis.error_type = 'critical'
        elif error_level == 'high':
            score_boost = self.priority_scoring.get('high_level', 25)
            analysis.priority += score_boost
            analysis.reasons.append("高错误级别")
            analysis.error_type = 'high'

            # 针对 warning 类型，如果包含文件路径（代码相关），给予额外加分
            if 'warning' in errid.lower():
                has_file_path = bool(self._extract_file_paths(errid))
                if has_file_path:
                    analysis.priority += 10  # 额外加 10 分，使代码警告从 35 提升到 45
                    analysis.reasons.append("代码相关的编译警告")
                    analysis.flags['code_warning'] = True
        elif error_level == 'medium':
            score_boost = self.priority_scoring.get('medium_level', 15)
            analysis.priority += score_boost
            analysis.reasons.append("中等错误级别")
            analysis.error_type = 'medium'

        # 5. 代码相关性检查
        if self._is_code_related(errid):
            score_boost = self.priority_scoring.get('code_related', 20)
            analysis.priority += score_boost
            analysis.reasons.append("代码编译相关错误")
            analysis.flags['code_related'] = True

        # 6. 长度和复杂度评估
        optimal_min = self.length_eval.get('optimal_min', 80)
        optimal_max = self.length_eval.get('optimal_max', 300)
        if optimal_min <= len(errid) <= optimal_max:
            score_boost = self.priority_scoring.get('appropriate_length', 10)
            analysis.priority += score_boost
            analysis.reasons.append("适中的错误信息长度")

        # 确保优先级在合理范围内
        analysis.priority = min(analysis.priority, ErrorPriority.CRITICAL.value)

        return analysis
    
    def _is_environment_error(self, errid: str) -> bool:
        """检查是否为环境配置错误"""
        for pattern in self.environment_blacklist:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False
        
    def _is_high_value_error(self, errid: str) -> bool:
        """检查是否为高价值错误"""
        for pattern in self.value_whitelist:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False
        
    def _extract_file_paths(self, errid: str) -> List[str]:
        """提取错误中的文件路径"""
        file_paths = []
        for pattern in self.file_path_patterns:
            matches = re.findall(pattern, errid)
            file_paths.extend(matches)
        return list(set(file_paths))  # 去重
        
    def _detect_error_level(self, errid: str) -> str:
        """检测错误级别"""
        errid_lower = errid.lower()
        
        for level, keywords in self.error_keywords.items():
            for keyword in keywords:
                if keyword.lower() in errid_lower:
                    return level
        return ""
    
    def _is_code_related(self, errid: str) -> bool:
        """检查是否与代码相关"""
        for pattern in self.code_positive_patterns:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False
        
    def _extract_error_signature(self, errid: str) -> str:
        """提取错误的核心签名，用于去重"""
        # 移除 stderr.eid. 和 stderr.msg. 前缀
        signature = re.sub(r'^stderr\.(eid|msg)\.', '', errid)
        
        # 移除 .message 后缀
        signature = re.sub(r'\.message$', '', signature)
        
        # 规范化路径中的行号列号为占位符（因为具体位置可能不同，但核心错误相同）
        signature = re.sub(r':\d+:\d+', ':##:##', signature)
        
        # 规范化参数编号（1st, 2nd等）
        signature = re.sub(r'#(st|nd|rd|th)_parameter', '#N_parameter', signature)
        
        # 移除具体的错误标志如 [-Werror=attribute-warning]
        signature = re.sub(r'\[-W[^]]*\]', '', signature)
        
        return signature.strip()
    
    def _group_similar_errors(self, errids: List[str]) -> Dict[str, List[str]]:
        """将相似的错误归组"""
        groups = {}
        
        for errid in errids:
            signature = self._extract_error_signature(errid)
            if signature not in groups:
                groups[signature] = []
            groups[signature].append(errid)
        
        return groups
    
    def _categorize_error(self, errid: str) -> str:
        """
        简单按错误级别分类
        只区分 critical, error, warning, info
        """
        errid_lower = errid.lower()

        # Critical 级别 (panic, fatal, 严重内存错误等)
        if any(keyword in errid_lower for keyword in ['panic', 'fatal', 'kernel panic']):
            return 'critical'

        # 内存安全相关也视为 critical
        if re.search(r'__.*overflow|fortify.*string|detected_.*beyond_size|buffer.*overflow|memory.*leak', errid_lower):
            return 'critical'

        # Error 级别
        if any(keyword in errid_lower for keyword in ['error', 'fail', 'failed']):
            return 'error'

        # Warning 级别
        if any(keyword in errid_lower for keyword in ['warning', 'warn', 'deprecated']):
            return 'warning'

        # 默认为 info
        return 'info'
    
    def extract_coarse_signature(self, errid: str) -> str:
        """
        提取粗粒度错误签名，用于聚类相似错误

        策略：将同一文件 + 同一错误类型的错误归为一组
        这样可以将同一个根因导致的多个错误聚合在一起

        示例：
        - nbl_service.c 的所有 function_declaration 错误 -> "nbl_core/nbl_service.c::function_declaration"
        - 这些错误很可能是同一个 commit 引入的（比如缺少某个头文件）

        Args:
            errid: 原始错误ID字符串

        Returns:
            粗粒度签名字符串，格式为 "file_path::error_type"
        """
        # 1. 提取文件路径（去除行号）
        # 支持的文件扩展名
        file_pattern = r'([/\w._-]+\.(c|h|cpp|hpp|cc|cxx|py|rs|go|java|js|ts|sh)):'
        file_match = re.search(file_pattern, errid)

        if file_match:
            file_path = file_match.group(1)
            # 规范化：保留最后2级目录 + 文件名
            # 例如: drivers/net/ethernet/nebula-matrix/nbl/nbl_core/nbl_service.c
            #   -> nbl_core/nbl_service.c
            parts = file_path.split('/')
            if len(parts) >= 2:
                file_key = '/'.join(parts[-2:])
            else:
                file_key = parts[-1]
        else:
            # 如果没有文件路径，尝试从前缀提取关键信息
            # 支持通用的 suite.eid.xxx 格式
            # 例如: ltp.eid.test_case -> file_key='ltp'
            prefix_match = re.match(r'^([\w-]+)\.eid\.', errid)
            if prefix_match:
                suite_name = prefix_match.group(1)
                # stderr.eid 通常不代表具体文件/套件，作为特殊情况处理
                if suite_name == 'stderr':
                    file_key = 'stderr'
                else:
                    file_key = suite_name
            else:
                file_key = 'unknown_file'

        # 2. 获取错误类型
        error_type = self._categorize_error(errid)

        # 3. 组合签名：文件路径 + 错误类型
        signature = f"{file_key}::{error_type}"

        return signature

    def _should_keep_multiple_categories(self, error_groups: Dict[str, List[str]]) -> bool:
        """
        判断是否应该保留多个错误类别进行并行 bisect

        规则：
        1. 如果包含不同子系统的错误，应该保留（可能是不同 commit 引入）
        2. 如果只是同一类错误的重复，只保留一个代表
        """
        # 按错误类别分组
        categories = {}
        for signature, errids in error_groups.items():
            for errid in errids:
                category = self._categorize_error(errid)
                if category not in categories:
                    categories[category] = []
                categories[category].extend(errids)
                break  # 每个签名组只取第一个进行分类
        
        # 如果有多个不同类别，且都不是一般性错误，则应该保留多个
        significant_categories = [cat for cat in categories.keys() if cat != 'general']
        
        return len(significant_categories) >= 2
    
    def _select_best_representative(self, error_group: List[str]) -> str:
        """从一组相似错误中选择最佳代表"""
        # 优先级规则：
        # 1. 优先选择 stderr.eid.（而不是 stderr.msg.）
        # 2. 优先选择更短的（通常更直接）
        # 3. 优先选择不带 .message 后缀的
        
        eid_errors = [e for e in error_group if e.startswith('stderr.eid.')]
        if eid_errors:
            candidates = eid_errors
        else:
            candidates = error_group
        
        # 过滤掉 .message 后缀的版本
        non_message_errors = [e for e in candidates if not e.endswith('.message')]
        if non_message_errors:
            candidates = non_message_errors
        
        # 选择最短的作为代表（通常更直接）
        return min(candidates, key=len)
    
    def _select_representatives_by_category(self, error_groups: Dict[str, List[str]]) -> List[str]:
        """
        按错误类别选择代表，支持多类别并行 bisect
        """
        # 按错误类别分组
        category_groups = {}
        for signature, group in error_groups.items():
            representative = self._select_best_representative(group)
            category = self._categorize_error(representative)
            
            if category not in category_groups:
                category_groups[category] = []
            category_groups[category].append((representative, len(group), signature))
        
        # 选择每个类别的最佳代表
        representatives = []
        for category, candidates in category_groups.items():
            # 排序：优先选择代表更多原始错误的，然后按长度
            candidates.sort(key=lambda x: (-x[1], len(x[0])))
            best_rep = candidates[0][0]
            representatives.append(best_rep)
            
            if len(candidates) > 1:
                logger.debug(f"错误类别 '{category}': 从 {len(candidates)} 个候选中选择代表 -> {best_rep[:60]}...")
        
        return representatives
    
    def filter_errids(self, errids: List[str], max_count: int = None, min_priority: int = None, whitelist: set = None) -> List[Tuple[str, ErrorAnalysis]]:
        """
        智能筛选 error IDs，返回多个不同类别的有效错误

        Args:
            errids: 原始错误ID列表
            max_count: 最大返回数量（如果为None则使用配置文件中的默认值）
            min_priority: 最小优先级阈值（如果为None则使用配置文件中的默认值）
            whitelist: 白名单错误ID集合，会获得优先级加成

        Returns:
            筛选后的错误ID和分析结果列表，每个errid都是原始完整字符串
        """
        # 热重载配置检查
        self.reload_config_if_changed()

        # 使用配置文件中的默认参数
        if max_count is None:
            max_count = self.default_params.get('max_count', 10)
        if min_priority is None:
            min_priority = self.default_params.get('min_priority', 40)

        logger.info(f"开始智能筛选 {len(errids)} 个错误ID | max_count={max_count}, min_priority={min_priority}")

        # 第一步：过滤掉环境错误和低价值错误
        valid_errids = []
        for errid in errids:
            analysis = self.analyze_errid(errid)

            # 白名单优先级加成
            if whitelist and errid in whitelist:
                whitelist_boost = self.default_params.get('whitelist_boost', 20)
                analysis.priority += whitelist_boost
                analysis.reasons.append("在白名单中")

            if analysis.priority >= min_priority:
                valid_errids.append((errid, analysis))  # 保留原始完整字符串
        
        logger.info(f"过滤后剩余 {len(valid_errids)} 个有效错误ID")

        if not valid_errids:
            return []

        # 简化：只按优先级排序并限制数量，不做复杂的分类和代表选择
        # 按优先级降序排列
        valid_errids.sort(key=lambda x: -x[1].priority)

        # 限制返回数量
        result = valid_errids[:max_count]

        # 统计错误级别分布（仅用于日志）
        level_counts = {}
        for errid, analysis in result:
            level = self._categorize_error(errid)
            level_counts[level] = level_counts.get(level, 0) + 1

        logger.info(f"最终选择 {len(result)} 个错误ID | 级别分布: {level_counts}")

        # 记录选择结果
        for i, (errid, analysis) in enumerate(result, 1):
            level = self._categorize_error(errid)
            logger.debug(f"选择 {i}: 级别={level}, 优先级={analysis.priority}")
            logger.debug(f"  原因: {', '.join(analysis.reasons)}")
            logger.debug(f"  error_id: {errid[:100]}...")

        return result
    
    def get_regression_strategy_recommendation(self, success_rate: float, coverage_rate: float) -> Dict[str, any]:
        """
        基于成功率和覆盖率推荐regression策略
        
        Args:
            success_rate: 当前bisect成功率
            coverage_rate: 当前错误覆盖率
            
        Returns:
            策略推荐
        """
        recommendation = {
            'strategy': 'hybrid',  # whitelist, blacklist, hybrid
            'reasons': [],
            'parameters': {}
        }
        
        if success_rate > 0.8 and coverage_rate < 0.3:
            # 高成功率但低覆盖率：应该放宽筛选
            recommendation['strategy'] = 'blacklist'
            recommendation['reasons'].append("成功率高但覆盖率低，建议使用黑名单模式扩大覆盖")
            recommendation['parameters'] = {
                'min_priority': 30,  # 降低阈值
                'max_count': 15,     # 增加数量
            }
        elif success_rate < 0.5:
            # 低成功率：应该提高筛选标准
            recommendation['strategy'] = 'whitelist'
            recommendation['reasons'].append("成功率低，建议使用白名单模式提高质量")
            recommendation['parameters'] = {
                'min_priority': 60,  # 提高阈值
                'max_count': 5,      # 减少数量
            }
        else:
            # 平衡模式
            recommendation['strategy'] = 'hybrid'
            recommendation['reasons'].append("成功率和覆盖率平衡，使用混合模式")
            recommendation['parameters'] = {
                'min_priority': 40,
                'max_count': 10,
                'use_whitelist_boost': True,  # 对白名单中的errid给予优先级加成
            }
            
        return recommendation
    
    def should_use_llm_judgment(self, errid: str, analysis: ErrorAnalysis) -> bool:
        """
        判断是否需要使用LLM进行进一步判断
        
        目前的规则：
        1. 优先级在边界区间的（35-45）
        2. 包含复杂语境的错误
        3. 新型错误模式
        """
        # 优先级边界判断
        if 35 <= analysis.priority <= 45:
            return True
            
        # 复杂语境判断（包含多种信号但不确定）
        has_multiple_signals = (
            len(analysis.reasons) >= 3 and
            analysis.flags.get('has_file_path', False) and
            len(errid) > 100
        )
        
        if has_multiple_signals:
            return True
            
        # 新型错误模式（未被现有规则充分覆盖）
        if (analysis.priority > 0 and 
            len(analysis.reasons) <= 1 and 
            not any(keyword in errid.lower() for keywords in self.error_keywords.values() for keyword in keywords)):
            return True
            
        return False

    def should_filter_build_task(self, full_text_kv: str, git_url: str = None) -> Tuple[bool, str]:
        """
        判断构建任务是否应该被过滤

        Args:
            full_text_kv: 任务的 full_text_kv 字段
            git_url: Git 仓库 URL（如果已经提取）

        Returns:
            (should_filter, reason): 是否过滤及原因
        """
        # 如果未启用构建任务过滤，不过滤
        if not self.build_task_filters.get('enable_build_filtering', False):
            return False, ""

        # 检查是否为 makepkg 构建任务
        is_makepkg = False
        if full_text_kv:
            # 检查多种 makepkg 相关的模式
            makepkg_patterns = [
                r'suite=(?:makepkg|pkgbuild)',
                r'pp\.makepkg\.',
                r'program\.makepkg\.'
            ]
            for pattern in makepkg_patterns:
                if re.search(pattern, full_text_kv, re.IGNORECASE):
                    is_makepkg = True
                    break

        # 如果不是 makepkg 任务，不过滤
        if not is_makepkg:
            return False, ""

        # 如果没有配置允许的仓库列表，不过滤
        if not self.allowed_kernel_repos:
            return False, ""

        # 如果没有 git_url，尝试从 full_text_kv 提取
        if not git_url and full_text_kv:
            # 简单提取 git URL
            url_pattern = r'(?:ss\.linux\._url|pp\.makepkg\._url)=([^\s]+)'
            match = re.search(url_pattern, full_text_kv)
            if match:
                git_url = match.group(1)

        # 如果仍然没有 git_url，默认过滤（安全起见）
        if not git_url:
            return True, "makepkg 任务缺少 git_url"

        # 检查是否匹配允许的内核仓库
        for pattern in self.allowed_kernel_repos:
            if re.search(pattern, git_url, re.IGNORECASE):
                # 匹配到允许的仓库，不过滤
                return False, ""

        # 不在允许列表中，应该过滤
        repo_name = git_url.split('/')[-1] if '/' in git_url else git_url
        return True, f"makepkg 任务的仓库 {repo_name} 不在允许列表中"

# 使用示例和测试函数
def test_errid_intelligence():
    """测试函数"""
    intelligence = ErridIntelligence()
    
    # 使用用户提供的真实样本
    test_samples = [
        # 样本1：重复的fortify-string错误
        [
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow'declared_with_attribute_error:detected_read_beyond_size_of_object(#st_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow'declared_with_attribute_error:detected_read_beyond_size_of_object(#st_parameter).message",
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow2'declared_with_attribute_error:detected_read_beyond_size_of_object(#nd_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow2'declared_with_attribute_error:detected_read_beyond_size_of_object(#nd_parameter).message",
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__write_overflow'declared_with_attribute_error:detected_write_beyond_size_of_object(#st_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__write_overflow'declared_with_attribute_error:detected_write_beyond_size_of_object(#st_parameter).message",
        ],
        
        # 样本2：环境错误（应该被过滤）
        [
            "stderr.eid.curl:(#)The_requested_URL_returned_error",
            "stderr.msg.curl:(#)The_requested_URL_returned_error.message",
            "stderr.eid.Error:File_already_exists_on_server:/srv/file-store/ss/pkgbuild/linux/aarch64/randconfig-linux-#-#/#/System.map",
            "stderr.eid.has_stderr",
        ],
        
        # 样本3：复杂的多类型编译错误
        [
            "last_state.eid.exit_fail",
            "stderr.eid.drivers/pinctrl/qcom/pinctrl-msm.c:#:#:error:'pinmux_generic_get_function_count'undeclared_here(not_in_a_function)",
            "stderr.msg.drivers/pinctrl/qcom/pinctrl-msm.c:#:#:error:'pinmux_generic_get_function_count'undeclared_here(not_in_a_function).message",
            "stderr.eid.drivers/pinctrl/qcom/pinctrl-msm.c:#:#:error:'pinmux_generic_get_function_name'undeclared_here(not_in_a_function)",
            "stderr.eid.drivers/pinctrl/qcom/pinctrl-msm.c:#:#:error:implicit_declaration_of_function'pinmux_generic_add_pinfunction'",
            "stderr.eid.==>ERROR:A_failure_occurred_in_build()",
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow'declared_with_attribute_error:detected_read_beyond_size_of_object(#st_parameter)",
            "stderr.eid.has_stderr"
        ]
    ]
    
    for i, sample in enumerate(test_samples, 1):
        print(f"\n{'='*60}")
        print(f"测试样本 {i}: {len(sample)} 个错误ID")
        print(f"{'='*60}")
        
        results = intelligence.filter_errids(sample, max_count=5, min_priority=30)
        
        print(f"筛选结果: 从 {len(sample)} 个中选择了 {len(results)} 个")
        
        for j, (errid, analysis) in enumerate(results, 1):
            print(f"\n{j}. 优先级: {analysis.priority}")
            print(f"   Error ID: {errid}")
            print(f"   原因: {', '.join(analysis.reasons)}")
            print(f"   错误类型: {analysis.error_type}")
            print(f"   文件路径: {analysis.file_paths}")
        
        if not results:
            print("   ❌ 所有错误都被过滤掉了（可能都是环境错误）")

if __name__ == "__main__":
    test_errid_intelligence()