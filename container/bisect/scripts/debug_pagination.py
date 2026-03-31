#!/usr/bin/env python3
"""Debug pagination query - check field names and data format returned by sql_select"""

import os
import sys
import time
import json

# Add paths
lkp_src = os.environ.get('LKP_SRC', '/c/lkp-tests')
sys.path.insert(0, os.path.join(os.environ.get('CCI_SRC', '/srv/cci'), 'container/bisect/lib'))
sys.path.insert(0, lkp_src)
sys.path.insert(0, os.path.join(lkp_src, 'sbin/bisect'))

from lkp_bisect.db.manticore import ManticoreClient

host = os.environ.get('MANTICORE_HOST', 'localhost')
port = int(os.environ.get('MANTICORE_WRITE_PORT', '9308'))
print(f"Connecting to ManticoreSearch at {host}:{port}")
c = ManticoreClient(host=host, port=port)
t = int(time.time() - 720 * 3600)

# Page 1: no id filter
sql1 = f"""
    SELECT id, j.errid, full_text_kv, submit_time,
    j.ss.linux.commit as linux_commit,
    j.pp.makepkg.commit as makepkg_commit
    FROM jobs
    WHERE j.errid IS NOT NULL
    AND j.job_stage = 'finish'
    AND j.job_data_readiness = 'complete'
    AND j.bad_job_id IS NULL
    AND submit_time >= {t}
    ORDER BY id DESC
    LIMIT 3
"""

print("=" * 60)
print("Page 1 (no id filter)")
print("=" * 60)
r1 = c.sql_select(sql1)
if not r1:
    print("ERROR: empty result")
    sys.exit(1)

print(f"Rows returned: {len(r1)}")
item = r1[0]
print(f"\nFirst row keys: {sorted(item.keys())}")
print(f" id: {repr(item.get('id'))} (type: {type(item.get('id')).__name__})")
print(f" j.errid: {repr(item.get('j.errid', 'KEY_MISSING'))}")
print(f" errid: {repr(item.get('errid', 'KEY_MISSING'))}")
print(f" full_text_kv: {type(item.get('full_text_kv')).__name__} len={len(str(item.get('full_text_kv', '')))}")
print(f" linux_commit: {repr(item.get('linux_commit', 'KEY_MISSING'))}")
print(f" makepkg_commit: {repr(item.get('makepkg_commit', 'KEY_MISSING'))}")

# Test int conversion (the line that might throw)
try:
    bad_job_id = str(int(item["id"]))
    print(f" str(int(id)): {bad_job_id} OK")
except Exception as e:
    print(f" str(int(id)): FAILED - {e}")

# Page 2: with id filter
last_id = r1[-1].get('id')
print(f"\n{'=' * 60}")
print(f"Page 2 (id < {last_id})")
print("=" * 60)

sql2 = f"""
    SELECT id, j.errid, full_text_kv, submit_time,
    j.ss.linux.commit as linux_commit,
    j.pp.makepkg.commit as makepkg_commit
    FROM jobs
    WHERE j.errid IS NOT NULL
    AND j.job_stage = 'finish'
    AND j.job_data_readiness = 'complete'
    AND j.bad_job_id IS NULL
    AND submit_time >= {t}
    AND id < {last_id}
    ORDER BY id DESC
    LIMIT 3
"""

r2 = c.sql_select(sql2)
if not r2:
    print("ERROR: page 2 empty (id filter might not work)")
    sys.exit(1)

print(f"Rows returned: {len(r2)}")
item2 = r2[0]
print(f"First row keys: {sorted(item2.keys())}")
print(f" id: {repr(item2.get('id'))}")

# Check for overlap
ids1 = {r.get('id') for r in r1}
ids2 = {r.get('id') for r in r2}
overlap = ids1 & ids2
print(f"\nOverlap check: page1 ids={ids1}, page2 ids={ids2}")
print(f"Overlap: {overlap if overlap else 'NONE (good)'}")

# Check errid extraction
print(f"\n{'=' * 60}")
print("errid extraction test (first 5 rows)")
print("=" * 60)
all_rows = r1 + r2
for i, row in enumerate(all_rows[:5]):
    errids = row.get("j.errid", [])
    print(f" row {i}: id={row.get('id')} errid_type={type(errids).__name__} errid_len={len(errids) if isinstance(errids, list) else 'N/A'} sample={str(errids)[:100]}")

print("\nDone.")
