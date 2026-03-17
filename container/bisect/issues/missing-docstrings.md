# Issue: Add module docstrings to Python files

## Status: DONE

## Background

Many `.py` files have empty or missing module-level docstrings. These should be added
for consistency with CODEBASE.md descriptions and to help both humans and AI tools
understand each module's purpose without reading the full code.

## Resolution summary

Module-level docstrings are now present across all Python modules under
`container/bisect/`.

- Added missing module docstrings to runtime modules (`app/*`, `core/*`, `lib/*`)
- Added package docstrings to `__init__.py` modules (`core/tests`, `metrics`, `validators`)
- Updated validator module docstrings to English

## Verification

Run this check from repo root:

```bash
python3 - <<'PY'
import ast
import pathlib

root = pathlib.Path("container/bisect")
missing = []
for path in root.rglob("*.py"):
    try:
        module = ast.parse(path.read_text(errors="ignore"))
    except Exception:
        continue
    if ast.get_docstring(module, clean=False) is None:
        missing.append(path)

print(f"missing module docstrings: {len(missing)}")
for item in missing:
    print(item)
PY
```

Expected result: `missing module docstrings: 0`

## Standard format

Each file should have a brief English docstring matching the description in `CODEBASE.md`:

```python
#!/usr/bin/env python3
"""
Bisect Consumer — processes individual bisect tasks.

Clones repo, runs git bisect, parses results, updates task status.
"""
```

## Reference

See `container/bisect/CODEBASE.md` for per-file descriptions to use as docstrings.
