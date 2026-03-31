# Issue: Verification Reuse Quality Risks

## Status

OPEN

## Scope

Review reuse propagation paths after a bisect task reaches verified success, with focus on:

- `container/bisect/lib/bisect_utils.py`
- `container/bisect/core/task_processor.py`
- `container/bisect/validators/success_task_validator.py`
- `container/bisect/core/bisect_consumer.py`

## Background

The current verification pipeline now has:

- bounded verification queue concurrency
- timeout recovery with retry/backoff
- startup recovery for `verifying` tasks
- verification queue status API/CLI

These fixes improve queue stability, but they do not fully constrain how a verified result
can propagate to additional tasks through `introduced_errids`.

## Findings

### 1) High: `introduced_errids` propagation still bypasses the new queue gate

`mark_introduced_errid_tasks_for_verification()` currently marks matching wait tasks
directly to `bisect_status='verifying'`.

Impact:

- bypasses the new `pending_verification -> admission control -> verifying` flow
- can still create bursts of verification work outside `MAX_VERIFYING_TASKS`
- makes queue behavior inconsistent between signature-based reuse and introduced-errid reuse

Relevant code:

- `container/bisect/lib/bisect_utils.py`

### 2) High: reused success can continue to act as a reuse source

A task verified by `SuccessTaskValidator` is written back as `bisect_status='success'`
with `verification_status='verified'` and `introduced_errids`.

That means a reused result can trigger:

- signature-based reuse of similar wait tasks
- introduced-errid-based propagation to other wait tasks

Impact:

- creates multi-hop reuse chains
- weakens the distinction between "original bisect success" and "reused verified success"
- increases the blast radius if an earlier reused result is misleading

### 3) Medium: introduced-errid propagation lacks explicit source-quality gating

Signature-based reuse is filtered through the success cache and `confidence` threshold.
The introduced-errid propagation path does not apply an equivalent source check before
marking additional tasks.

Current matching criteria are mainly:

- same repo
- `error_id` exact match within `introduced_errids`
- task currently in `wait`

Impact:

- broader propagation than the main reuse path
- quality depends on exact errid list accuracy, but there is no explicit policy gate

### 4) Medium: no explicit propagation-depth limit

There is no field or policy limiting propagation to:

- one hop only
- original full-bisect successes only
- non-reused sources only

Impact:

- repeated reuse can accumulate across task generations
- harder to reason about provenance and trust level of downstream results

## Why this matters

This does not automatically mean the final result is wrong.

There are existing safety properties:

- same-repo matching
- exact `error_id` match for introduced-errid propagation
- boundary verification before reused task becomes `verified`
- timeout/failure paths return tasks for retry or independent bisect

However, the remaining propagation path is looser than the newly fixed verification queue
path and can still affect result quality and system load.

## Recommended Fix Plan

1. Route introduced-errid propagation into `pending_verification`
   - stop writing `bisect_status='verifying'` directly
   - let all reuse-triggered validation share one admission-control path

2. Add explicit reuse-source eligibility checks
   - require `j.verification_status='verified'`
   - and require source eligibility such as:
     - `j.confidence` >= configured threshold, or
     - `j.reusable_as_verification_source != false`

3. Consider limiting propagation depth
   - allow only original bisect successes to propagate
   - or record `reuse_depth` and reject depth > 1

4. Make provenance visible
   - distinguish:
     - original bisect success
     - reused verified success
     - reused but unverified success

## Suggested Validation

- verify introduced-errid path now enters `pending_verification`, not `verifying`
- verify `MAX_VERIFYING_TASKS` is still respected under introduced-errid fan-out
- verify reused success without source eligibility cannot trigger further propagation
- verify logs and status API reflect propagation source and queue pressure
