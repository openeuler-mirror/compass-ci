#!/usr/bin/env python3
"""Guards against bisect-table schema drift in write paths."""

import ast
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
SQL_SCHEMA = REPO_ROOT / "sbin" / "manti-table-bisect.sql"
PY_ROOT = REPO_ROOT / "container" / "bisect"


def _load_bisect_columns():
    text = SQL_SCHEMA.read_text(encoding="utf-8")
    match = re.search(r"CREATE TABLE\s+bisect\s*\((.*?)\)\s*charset_table", text, re.S | re.I)
    assert match, "Cannot parse bisect table schema from sbin/manti-table-bisect.sql"
    columns_block = match.group(1)
    columns = set()
    for raw_line in columns_block.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("--"):
            continue
        col = line.split()[0].rstrip(",")
        columns.add(col)
    return columns


def _iter_py_files():
    for path in PY_ROOT.rglob("*.py"):
        if "/tests/" in str(path):
            continue
        yield path


def _literal_string(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def test_bisect_write_dict_keys_match_schema_columns():
    allowed_columns = _load_bisect_columns()
    errors = []

    for py_file in _iter_py_files():
        src = py_file.read_text(encoding="utf-8")
        tree = ast.parse(src, filename=str(py_file))

        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            if not isinstance(node.func, ast.Attribute):
                continue
            if node.func.attr not in {"update", "insert"}:
                continue
            if len(node.args) < 3:
                continue

            table_name = _literal_string(node.args[0])
            if table_name != "bisect":
                continue

            payload = node.args[2]
            if not isinstance(payload, ast.Dict):
                continue

            for key_node in payload.keys:
                key = _literal_string(key_node)
                if key and key not in allowed_columns:
                    errors.append(f"{py_file}:{key_node.lineno} invalid top-level bisect field '{key}'")

    assert not errors, "Schema mismatch in bisect update/insert payloads:\n" + "\n".join(errors)


def test_no_verified_at_order_by_on_bisect_table():
    # verified_at lives in j JSON, not top-level; ORDER BY verified_at is invalid.
    offenders = []
    pattern = re.compile(r"ORDER\s+BY\s+verified_at", re.I)

    for py_file in _iter_py_files():
        text = py_file.read_text(encoding="utf-8")
        if pattern.search(text):
            offenders.append(str(py_file))

    assert not offenders, "Use updated_at (or j.verified_at) instead of ORDER BY verified_at:\n" + "\n".join(offenders)
