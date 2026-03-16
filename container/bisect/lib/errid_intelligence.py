#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Intelligent Error ID Filtering Module

Implements a multi-layer intelligent filtering algorithm to select the most
suitable errors for bisect from a large pool of error IDs.
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
    """Error priority levels"""
    CRITICAL = 100    # Critical error, highest priority
    HIGH = 80        # High priority
    MEDIUM = 60      # Medium priority
    LOW = 40         # Low priority
    IGNORE = 0       # Ignore

@dataclass
class ErrorAnalysis:
    """Error analysis result"""
    errid: str
    original_errid: str = ""  # Preserve original error_id for bisect matching
    priority: int = 0
    reasons: List[str] = field(default_factory=list)
    flags: Dict[str, bool] = field(default_factory=dict)
    file_paths: List[str] = field(default_factory=list)
    error_type: str = ""

class ErridIntelligence:
    """Intelligent Error ID filter"""

    # Config path resolution order:
    #   1. Explicit config_path argument
    #   2. ERRID_FILTER_CONFIG env var (for mounted/overridden configs)
    #   3. Default path under CCI_SRC
    DEFAULT_CONFIG_SUBPATH = 'container/bisect/config/errid_filters.yaml'

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize intelligent filter

        Args:
            config_path: config file path; if None, resolved from env vars
        """
        if config_path is None:
            config_path = os.environ.get(
                'ERRID_FILTER_CONFIG',
                os.path.join(os.environ['CCI_SRC'], self.DEFAULT_CONFIG_SUBPATH)
            )

        self.config_path = config_path
        self.config_mtime = 0  # Config file mtime (for hot-reload)
        self.config = {}

        self._load_config()

        logger.info(f"ErridIntelligence initialized | config: {self.config_path}")
        logger.info(f"config version: {self.config.get('version', 'unknown')}")
        logger.info(f"environment blacklist rules: {len(self.environment_blacklist)}")
        logger.info(f"high-value whitelist rules: {len(self.value_whitelist)}")
        logger.info(f"code-related patterns: {len(self.code_positive_patterns)}")
        logger.info(f"error categories: {len(self.error_categories)}")

    def _load_config(self):
        """Load filtering rules from YAML config file"""
        try:
            config_file = Path(self.config_path)

            if not config_file.exists():
                logger.warning(f"Config file not found: {self.config_path}, using defaults")
                self._load_default_config()
                return

            current_mtime = config_file.stat().st_mtime
            if current_mtime == self.config_mtime and hasattr(self, 'file_path_patterns'):
                # Config unchanged and already loaded, skip
                return

            with open(config_file, 'r', encoding='utf-8') as f:
                self.config = yaml.safe_load(f)

            self.config_mtime = current_mtime

            # 1. Load file path recognition patterns
            self.file_path_patterns = [
                item['pattern'] for item in self.config.get('file_path_patterns', [])
            ]

            # 2. Load error keywords
            self.error_keywords = self.config.get('error_keywords', {})

            # 3. Load environment error blacklist
            self.environment_blacklist = [
                item['pattern'] for item in self.config.get('environment_blacklist', [])
            ]

            # 4. Load high-value whitelist (with priority boost)
            self.value_whitelist_data = self.config.get('value_whitelist', [])
            self.value_whitelist = [item['pattern'] for item in self.value_whitelist_data]

            # 5. Load code-related positive signals
            self.code_positive_patterns_data = self.config.get('code_positive_patterns', [])
            self.code_positive_patterns = [item['pattern'] for item in self.code_positive_patterns_data]

            # 6. Load error categories
            self.error_categories = self.config.get('error_categories', {})

            # 7. Load priority scoring rules
            self.priority_scoring = self.config.get('priority_scoring', {
                'has_file_path': 30,
                'critical_level': 40,
                'high_level': 25,
                'medium_level': 15,
                'code_related': 20,
                'appropriate_length': 10,
                'whitelist_match': 20
            })

            # 8. Load length evaluation rules
            self.length_eval = self.config.get('length_evaluation', {
                'min_length': 50,
                'max_length': 500,
                'optimal_min': 80,
                'optimal_max': 300
            })

            # 9. Load default parameters
            self.default_params = self.config.get('default_parameters', {
                'max_count': 6,
                'min_priority': 10,
                'whitelist_boost': 20
            })

            # 10. Load build task filtering rules
            self.build_task_filters = self.config.get('build_task_filters', {})
            if self.build_task_filters.get('enable_build_filtering', False):
                self.allowed_kernel_repos = [
                    item['pattern'] for item in self.build_task_filters.get('allowed_kernel_repos', [])
                ]
                logger.info(f"Build task filtering enabled | allowed kernel repos: {len(self.allowed_kernel_repos)}")
            else:
                self.allowed_kernel_repos = []

            logger.info(f"Config loaded successfully | version: {self.config.get('version', 'unknown')}")

        except Exception as e:
            logger.error(f"Failed to load config file: {str(e)}")
            logger.warning("Falling back to default config")
            self._load_default_config()

    def _load_default_config(self):
        """Load default config (used when config file is missing or fails to load)"""
        logger.info("Loading default hardcoded config")

        # File path regex patterns - enhanced, supports more formats
        self.file_path_patterns = [
            r'[\./\w-]+\.(?:h|c|cpp|py|rs|go|java|js):\d+:\d+',
            r'[\./\w-]+\.(?:h|c|cpp|py|rs|go|java|js):#:#:',
            r'\/[\w\.-/]+/[\w\.-]+\.\w+:\d+',
        ]

        # Error keywords (sorted by priority)
        self.error_keywords = {
            'critical': ['error', 'Error', 'ERROR', 'fatal', 'FATAL', 'panic', 'PANIC'],
            'high': ['warning', 'Warning', 'WARNING', 'fail', 'failed', 'FAIL', 'FAILED'],
            'medium': ['warn', 'WARN', 'deprecated', 'DEPRECATED'],
        }

        # Environment error blacklist (should be filtered out)
        # Note: error IDs may use - or _ as separators, patterns must support both
        self.environment_blacklist = [
            r'No.such.file.or.directory',
            r'command.not.found',
            r'Permission.denied',
            r'Connection.refused',
            r'Network.is.unreachable',
            r'/usr/bin/env.*not.*found',
            r'ruby.*not.*found',
            r'python.*not.*found',
            r'bash.*not.*found',
            r'.*\.rpm.*not.*found',
            r'package.*not.*available',
            r'repository.*not.*found',
            r'Failure.while.creating.working.copy.of.*git.repo',
            r'ambiguous.*not.found.in.the.build.directory',
            r'detect.arch.by.readelf.*gpg.error',
            r'git.update.cache.failed',
            r'curl.*The.*requested.*URL.*returned.*error',
            r'The.*requested.*URL.*returned.*error',
            r'curl:\(#?\d*\)',
            r'File.already.exists.on.server',
            r'/srv/file-store/.*already.exists',
            r'has_stderr$',
            r'upload.*error',
            r'download.*error',
            r'network.*timeout',
            r'^stderr\.eid\.install-',  # Install script errors
            r'install-m#',              # install command errors
            r'==>ERROR:A.failure.occurred.in.(build|prepare|package|check)\(\)',  # makepkg build process errors
            r'==>WARNING:Skipping',     # makepkg process warnings
            r'^last_state\.eid\.exit_fail$',
            r'^last_state\.eid\.test\..*exit_code\.\d+$',
        ]

        # Code-related positive signals
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

        # Whitelist: known high-value error types
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

        # Default scoring rules
        self.priority_scoring = {
            'has_file_path': 30,
            'critical_level': 40,
            'high_level': 25,
            'medium_level': 15,
            'code_related': 20,
            'appropriate_length': 10,
            'whitelist_match': 20
        }

        # Default length evaluation
        self.length_eval = {
            'min_length': 50,
            'max_length': 500,
            'optimal_min': 80,
            'optimal_max': 300
        }

        # Default parameters
        self.default_params = {
            'max_count': 6,
            'min_priority': 40,  # Raised to 40 to ensure task quality
            'whitelist_boost': 20
        }

        # Error categories (default)
        self.error_categories = {}

    def reload_config_if_changed(self):
        """Check if config file has been modified and reload if so (hot-reload)"""
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                return False

            current_mtime = config_file.stat().st_mtime
            if current_mtime != self.config_mtime:
                logger.info("Config file change detected, reloading...")
                self._load_config()
                return True

            return False

        except Exception as e:
            logger.error(f"Error checking config file modification: {str(e)}")
            return False

    def analyze_errid(self, errid: str) -> ErrorAnalysis:
        """Analyze a single error ID, return analysis result"""
        analysis = ErrorAnalysis(errid=errid, original_errid=errid)  # Preserve original full string

        # 1. Environment error check (blacklist)
        if self._is_environment_error(errid):
            analysis.priority = ErrorPriority.IGNORE.value
            analysis.reasons.append("environment/config error, not suitable for bisect")
            return analysis

        # 2. High-value error check (whitelist)
        if self._is_high_value_error(errid):
            analysis.priority = ErrorPriority.CRITICAL.value
            analysis.reasons.append("high-value error type")

        # 3. File path check
        file_paths = self._extract_file_paths(errid)
        if file_paths:
            analysis.file_paths = file_paths
            score_boost = self.priority_scoring.get('has_file_path', 30)
            analysis.priority += score_boost
            analysis.reasons.append(f"contains file paths: {len(file_paths)}")
            analysis.flags['has_file_path'] = True

        # 4. Error level check
        error_level = self._detect_error_level(errid)
        if error_level == 'critical':
            score_boost = self.priority_scoring.get('critical_level', 40)
            analysis.priority += score_boost
            analysis.reasons.append("critical error level")
            analysis.error_type = 'critical'
        elif error_level == 'high':
            score_boost = self.priority_scoring.get('high_level', 25)
            analysis.priority += score_boost
            analysis.reasons.append("high error level")
            analysis.error_type = 'high'

            # For warning type, if it contains file paths (code-related), give extra boost
            if 'warning' in errid.lower():
                has_file_path = bool(self._extract_file_paths(errid))
                if has_file_path:
                    analysis.priority += 10  # Extra 10 points, raises code warnings from 35 to 45
                    analysis.reasons.append("code-related compile warning")
                    analysis.flags['code_warning'] = True
        elif error_level == 'medium':
            score_boost = self.priority_scoring.get('medium_level', 15)
            analysis.priority += score_boost
            analysis.reasons.append("medium error level")
            analysis.error_type = 'medium'

        # 5. Code relevance check
        if self._is_code_related(errid):
            score_boost = self.priority_scoring.get('code_related', 20)
            analysis.priority += score_boost
            analysis.reasons.append("code compilation related error")
            analysis.flags['code_related'] = True

        # 6. Length and complexity evaluation
        optimal_min = self.length_eval.get('optimal_min', 80)
        optimal_max = self.length_eval.get('optimal_max', 300)
        if optimal_min <= len(errid) <= optimal_max:
            score_boost = self.priority_scoring.get('appropriate_length', 10)
            analysis.priority += score_boost
            analysis.reasons.append("appropriate error message length")

        # Ensure priority is within reasonable range
        analysis.priority = min(analysis.priority, ErrorPriority.CRITICAL.value)

        return analysis

    def _is_environment_error(self, errid: str) -> bool:
        """Check if this is an environment/config error"""
        for pattern in self.environment_blacklist:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False

    def _is_high_value_error(self, errid: str) -> bool:
        """Check if this is a high-value error"""
        for pattern in self.value_whitelist:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False

    def _extract_file_paths(self, errid: str) -> List[str]:
        """Extract file paths from error"""
        file_paths = []
        for pattern in self.file_path_patterns:
            matches = re.findall(pattern, errid)
            file_paths.extend(matches)
        return list(set(file_paths))  # Deduplicate

    def _detect_error_level(self, errid: str) -> str:
        """Detect error level"""
        errid_lower = errid.lower()

        for level, keywords in self.error_keywords.items():
            for keyword in keywords:
                if keyword.lower() in errid_lower:
                    return level
        return ""

    def _is_code_related(self, errid: str) -> bool:
        """Check if error is code-related"""
        for pattern in self.code_positive_patterns:
            if re.search(pattern, errid, re.IGNORECASE):
                return True
        return False

    def _extract_error_signature(self, errid: str) -> str:
        """Extract core error signature for deduplication"""
        # Remove stderr.eid. and stderr.msg. prefixes
        signature = re.sub(r'^stderr\.(eid|msg)\.', '', errid)

        # Remove .message suffix
        signature = re.sub(r'\.message$', '', signature)

        # Normalize line/column numbers to placeholders (specific positions may differ but core error is the same)
        signature = re.sub(r':\d+:\d+', ':##:##', signature)

        # Normalize parameter ordinals (1st, 2nd etc.)
        signature = re.sub(r'#(st|nd|rd|th)_parameter', '#N_parameter', signature)

        # Remove specific error flags like [-Werror=attribute-warning]
        signature = re.sub(r'\[-W[^]]*\]', '', signature)

        return signature.strip()

    def _group_similar_errors(self, errids: List[str]) -> Dict[str, List[str]]:
        """Group similar errors together"""
        groups = {}

        for errid in errids:
            signature = self._extract_error_signature(errid)
            if signature not in groups:
                groups[signature] = []
            groups[signature].append(errid)

        return groups

    def _categorize_error(self, errid: str) -> str:
        """
        Simple categorization by error level.
        Distinguishes: critical, error, warning, info
        """
        errid_lower = errid.lower()

        # Critical level (panic, fatal, severe memory errors, etc.)
        if any(keyword in errid_lower for keyword in ['panic', 'fatal', 'kernel panic']):
            return 'critical'

        # Memory safety related also considered critical
        if re.search(r'__.*overflow|fortify.*string|detected_.*beyond_size|buffer.*overflow|memory.*leak', errid_lower):
            return 'critical'

        # Error level
        if any(keyword in errid_lower for keyword in ['error', 'fail', 'failed']):
            return 'error'

        # Warning level
        if any(keyword in errid_lower for keyword in ['warning', 'warn', 'deprecated']):
            return 'warning'

        # Default to info
        return 'info'

    def extract_coarse_signature(self, errid: str) -> str:
        """
        Extract coarse-grained error signature for clustering similar errors.

        Strategy: group errors by same file + same error type.
        This aggregates multiple errors caused by the same root cause.

        Examples:
        - All function_declaration errors in nbl_service.c -> "nbl_core/nbl_service.c::function_declaration"
        - These errors are likely introduced by the same commit (e.g., missing a header file)
        - makepkg unmet-direct-dependencies-detected-for-CAN_DEV -> "makepkg::unmet-deps::CAN_DEV"

        Args:
            errid: original error ID string

        Returns:
            coarse-grained signature string, format "file_path::error_type" or special format
        """
        # Special handling: makepkg config dependency errors
        # Different CONFIG names should be tested independently, as they are usually introduced by different commits
        # e.g.: makepkg.eid.WARNING:unmet-direct-dependencies-detected-for-CAN_DEV
        #   vs.: makepkg.eid.WARNING:unmet-direct-dependencies-detected-for-ARCH_SUPPORTS_SCHED_SOFT_QUOTA
        # These two errors should have different signatures
        unmet_deps_match = re.search(r'unmet-direct-dependencies-detected-for-([A-Z0-9_]+)', errid)
        if unmet_deps_match:
            config_name = unmet_deps_match.group(1)
            return f"makepkg::unmet-deps::{config_name}"

        # 1. Extract file path (strip line numbers)
        # Supported file extensions
        file_pattern = r'([/\w._-]+\.(c|h|cpp|hpp|cc|cxx|py|rs|go|java|js|ts|sh)):'
        file_match = re.search(file_pattern, errid)

        if file_match:
            file_path = file_match.group(1)
            # Normalize: keep last 2 directory levels + filename
            # e.g.: drivers/net/ethernet/nebula-matrix/nbl/nbl_core/nbl_service.c
            #   -> nbl_core/nbl_service.c
            parts = file_path.split('/')
            if len(parts) >= 2:
                file_key = '/'.join(parts[-2:])
            else:
                file_key = parts[-1]
        else:
            # No file path found, try extracting key info from prefix
            # Supports generic suite.eid.xxx format
            # e.g.: ltp.eid.test_case -> file_key='ltp'
            prefix_match = re.match(r'^([\w-]+)\.eid\.', errid)
            if prefix_match:
                suite_name = prefix_match.group(1)
                # stderr.eid usually doesn't represent a specific file/suite, handle specially
                if suite_name == 'stderr':
                    file_key = 'stderr'
                else:
                    file_key = suite_name
            else:
                file_key = 'unknown_file'

        # 2. Get error type
        error_type = self._categorize_error(errid)

        # 3. Combine signature: file_path + error_type
        signature = f"{file_key}::{error_type}"

        return signature

    def _should_keep_multiple_categories(self, error_groups: Dict[str, List[str]]) -> bool:
        """
        Determine whether to keep multiple error categories for parallel bisect.

        Rules:
        1. If errors span different subsystems, keep them (may be from different commits)
        2. If just repetitions of the same error type, keep only one representative
        """
        categories = {}
        for signature, errids in error_groups.items():
            for errid in errids:
                category = self._categorize_error(errid)
                if category not in categories:
                    categories[category] = []
                categories[category].extend(errids)
                break  # Only categorize the first in each signature group

        # If there are multiple distinct categories (excluding general), keep multiple
        significant_categories = [cat for cat in categories.keys() if cat != 'general']

        return len(significant_categories) >= 2

    def _select_best_representative(self, error_group: List[str]) -> str:
        """Select the best representative from a group of similar errors"""
        # Priority rules:
        # 1. Prefer stderr.eid. (over stderr.msg.)
        # 2. Prefer shorter (usually more direct)
        # 3. Prefer without .message suffix

        eid_errors = [e for e in error_group if e.startswith('stderr.eid.')]
        if eid_errors:
            candidates = eid_errors
        else:
            candidates = error_group

        # Filter out .message suffix versions
        non_message_errors = [e for e in candidates if not e.endswith('.message')]
        if non_message_errors:
            candidates = non_message_errors

        # Select shortest as representative (usually more direct)
        return min(candidates, key=len)

    def _select_representatives_by_category(self, error_groups: Dict[str, List[str]]) -> List[str]:
        """
        Select representatives by error category, supporting multi-category parallel bisect
        """
        category_groups = {}
        for signature, group in error_groups.items():
            representative = self._select_best_representative(group)
            category = self._categorize_error(representative)

            if category not in category_groups:
                category_groups[category] = []
            category_groups[category].append((representative, len(group), signature))

        # Select best representative for each category
        representatives = []
        for category, candidates in category_groups.items():
            # Sort: prefer those representing more original errors, then by length
            candidates.sort(key=lambda x: (-x[1], len(x[0])))
            best_rep = candidates[0][0]
            representatives.append(best_rep)

            if len(candidates) > 1:
                logger.debug(f"Error category '{category}': selected representative from {len(candidates)} candidates -> {best_rep[:60]}...")

        return representatives

    def filter_errids(self, errids: List[str], max_count: int = None, min_priority: int = None, whitelist: set = None) -> List[Tuple[str, ErrorAnalysis]]:
        """
        Intelligently filter error IDs, return multiple valid errors from different categories.

        Args:
            errids: original error ID list
            max_count: max return count (if None, uses config default)
            min_priority: minimum priority threshold (if None, uses config default)
            whitelist: whitelist error ID set, receives priority boost

        Returns:
            filtered error IDs and analysis results, each errid is the original full string
        """
        # Hot-reload config check
        self.reload_config_if_changed()

        # Use config defaults
        if max_count is None:
            max_count = self.default_params.get('max_count', 10)
        if min_priority is None:
            min_priority = self.default_params.get('min_priority', 40)

        logger.info(f"Starting intelligent filtering of {len(errids)} error IDs | max_count={max_count}, min_priority={min_priority}")

        # Step 1: Filter out environment errors and low-value errors
        valid_errids = []
        for errid in errids:
            analysis = self.analyze_errid(errid)

            # Whitelist priority boost
            if whitelist and errid in whitelist:
                whitelist_boost = self.default_params.get('whitelist_boost', 20)
                analysis.priority += whitelist_boost
                analysis.reasons.append("in whitelist")

            if analysis.priority >= min_priority:
                valid_errids.append((errid, analysis))  # Preserve original full string

        logger.info(f"After filtering: {len(valid_errids)} valid error IDs remaining")

        if not valid_errids:
            return []

        # Sort by priority descending
        valid_errids.sort(key=lambda x: -x[1].priority)

        # Limit return count
        result = valid_errids[:max_count]

        # Log error level distribution
        level_counts = {}
        for errid, analysis in result:
            level = self._categorize_error(errid)
            level_counts[level] = level_counts.get(level, 0) + 1

        logger.info(f"Selected {len(result)} error IDs | level distribution: {level_counts}")

        # Log selection details
        for i, (errid, analysis) in enumerate(result, 1):
            level = self._categorize_error(errid)
            logger.debug(f"Selection {i}: level={level}, priority={analysis.priority}")
            logger.debug(f"  reasons: {', '.join(analysis.reasons)}")
            logger.debug(f"  error_id: {errid[:100]}...")

        return result

    def get_regression_strategy_recommendation(self, success_rate: float, coverage_rate: float) -> Dict[str, any]:
        """
        Recommend regression strategy based on success rate and coverage rate.

        Args:
            success_rate: current bisect success rate
            coverage_rate: current error coverage rate

        Returns:
            strategy recommendation
        """
        recommendation = {
            'strategy': 'hybrid',  # whitelist, blacklist, hybrid
            'reasons': [],
            'parameters': {}
        }

        if success_rate > 0.8 and coverage_rate < 0.3:
            # High success rate but low coverage: should relax filtering
            recommendation['strategy'] = 'blacklist'
            recommendation['reasons'].append("High success rate but low coverage, recommend blacklist mode to expand coverage")
            recommendation['parameters'] = {
                'min_priority': 30,  # Lower threshold
                'max_count': 15,     # Increase count
            }
        elif success_rate < 0.5:
            # Low success rate: should raise filtering standards
            recommendation['strategy'] = 'whitelist'
            recommendation['reasons'].append("Low success rate, recommend whitelist mode to improve quality")
            recommendation['parameters'] = {
                'min_priority': 60,  # Raise threshold
                'max_count': 5,      # Reduce count
            }
        else:
            # Balanced mode
            recommendation['strategy'] = 'hybrid'
            recommendation['reasons'].append("Success rate and coverage balanced, using hybrid mode")
            recommendation['parameters'] = {
                'min_priority': 40,
                'max_count': 10,
                'use_whitelist_boost': True,  # Give priority boost to whitelisted errids
            }

        return recommendation

    def should_use_llm_judgment(self, errid: str, analysis: ErrorAnalysis) -> bool:
        """
        Determine if LLM judgment is needed for further analysis.

        Current rules:
        1. Priority in borderline range (35-45)
        2. Contains complex context errors
        3. Novel error patterns
        """
        # Borderline priority check
        if 35 <= analysis.priority <= 45:
            return True

        # Complex context check (multiple signals but uncertain)
        has_multiple_signals = (
            len(analysis.reasons) >= 3 and
            analysis.flags.get('has_file_path', False) and
            len(errid) > 100
        )

        if has_multiple_signals:
            return True

        # Novel error pattern (not sufficiently covered by existing rules)
        if (analysis.priority > 0 and
            len(analysis.reasons) <= 1 and
            not any(keyword in errid.lower() for keywords in self.error_keywords.values() for keyword in keywords)):
            return True

        return False

    def should_filter_build_task(self, full_text_kv: str, git_url: str = None) -> Tuple[bool, str]:
        """
        Determine if a build task should be filtered.

        Args:
            full_text_kv: task's full_text_kv field
            git_url: Git repo URL (if already extracted)

        Returns:
            (should_filter, reason): whether to filter and the reason
        """
        # If build task filtering is not enabled, don't filter
        if not self.build_task_filters.get('enable_build_filtering', False):
            return False, ""

        # Check if this is a makepkg build task
        is_makepkg = False
        if full_text_kv:
            makepkg_patterns = [
                r'suite=(?:makepkg|pkgbuild)',
                r'pp\.makepkg\.',
                r'program\.makepkg\.'
            ]
            for pattern in makepkg_patterns:
                if re.search(pattern, full_text_kv, re.IGNORECASE):
                    is_makepkg = True
                    break

        # Not a makepkg task, don't filter
        if not is_makepkg:
            return False, ""

        # No allowed repos configured, don't filter
        if not self.allowed_kernel_repos:
            return False, ""

        # If no git_url, try extracting from full_text_kv
        if not git_url and full_text_kv:
            url_pattern = r'(?:ss\.linux\._url|pp\.makepkg\._url)=([^\s]+)'
            match = re.search(url_pattern, full_text_kv)
            if match:
                git_url = match.group(1)

        # If still no git_url, filter by default (for safety)
        if not git_url:
            return True, "makepkg task missing git_url"

        # Check if it matches allowed kernel repos
        for pattern in self.allowed_kernel_repos:
            if re.search(pattern, git_url, re.IGNORECASE):
                return False, ""

        # Not in allowed list, should be filtered
        repo_name = git_url.split('/')[-1] if '/' in git_url else git_url
        return True, f"makepkg task repo {repo_name} not in allowed list"

# Test function
def test_errid_intelligence():
    """Test function"""
    intelligence = ErridIntelligence()

    test_samples = [
        # Sample 1: repeated fortify-string errors
        [
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow'declared_with_attribute_error:detected_read_beyond_size_of_object(#st_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow'declared_with_attribute_error:detected_read_beyond_size_of_object(#st_parameter).message",
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow2'declared_with_attribute_error:detected_read_beyond_size_of_object(#nd_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__read_overflow2'declared_with_attribute_error:detected_read_beyond_size_of_object(#nd_parameter).message",
            "stderr.eid../include/linux/fortify-string.h:#:#:error:call_to'__write_overflow'declared_with_attribute_error:detected_write_beyond_size_of_object(#st_parameter)",
            "stderr.msg../include/linux/fortify-string.h:#:#:error:call_to'__write_overflow'declared_with_attribute_error:detected_write_beyond_size_of_object(#st_parameter).message",
        ],

        # Sample 2: environment errors (should be filtered)
        [
            "stderr.eid.curl:(#)The_requested_URL_returned_error",
            "stderr.msg.curl:(#)The_requested_URL_returned_error.message",
            "stderr.eid.Error:File_already_exists_on_server:/srv/file-store/ss/pkgbuild/linux/aarch64/randconfig-linux-#-#/#/System.map",
            "stderr.eid.has_stderr",
        ],

        # Sample 3: complex multi-type compile errors
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
        print(f"Test sample {i}: {len(sample)} error IDs")
        print(f"{'='*60}")

        results = intelligence.filter_errids(sample, max_count=5, min_priority=30)

        print(f"Filter result: selected {len(results)} from {len(sample)}")

        for j, (errid, analysis) in enumerate(results, 1):
            print(f"\n{j}. Priority: {analysis.priority}")
            print(f"   Error ID: {errid}")
            print(f"   Reasons: {', '.join(analysis.reasons)}")
            print(f"   Error type: {analysis.error_type}")
            print(f"   File paths: {analysis.file_paths}")

        if not results:
            print("   All errors were filtered out (likely all environment errors)")

if __name__ == "__main__":
    test_errid_intelligence()
