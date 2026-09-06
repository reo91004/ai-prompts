# Code Comment Hygiene Policy

## Core Rule
Comments must describe the code as it exists now.

Comments must not be used as evidence that the code is correct.

## Allowed Comments
Use comments for:

- non-obvious design intent;
- invariants;
- security assumptions;
- data provenance;
- boundary conditions;
- numerical or statistical assumptions;
- hardware timing or synthesis constraints;
- side-channel leakage model assumptions;
- citations to a specification, paper, protocol, or issue when the code depends on it.

## Disallowed Comments
Do not leave comments that describe:

- old bug history;
- phase history;
- temporary repair history;
- who or which agent made a change;
- excuses for incomplete implementation;
- TODO/FIXME/HACK/temporary placeholders;
- claims not supported by executable behavior;
- outdated assumptions or invalid constraints.

## Existing Comment Cleanup
When editing or reviewing code:

1. Search nearby comments, not just changed lines.
2. Check whether each comment still matches current behavior.
3. Rewrite comments that are useful but stale.
4. Delete comments that are obsolete or merely restate obvious code.
5. Move real unfinished work into carry-over docs or an issue tracker.
6. If a TODO remains by explicit user request, mark the artifact as incomplete and do not claim full acceptance.

## Docstrings

Do not docstring every function; a short, self-evident helper needs none.

Write a docstring for public API and research-risky functions (metrics, statistics, leakage models, data splits, capture). State only what the signature does not already show:

- what it computes;
- input shape or unit constraints that matter;
- statistical, numerical, or security assumptions;
- return shape;
- failure conditions.

Do not repeat type information already in type hints. A docstring that restates the signature is noise.

## Examples
Allowed:

```python
# 검증 세트에는 학습 데이터와 동일한 샘플 ID가 들어가지 않도록 분리한다.
```

Disallowed:

```python
# TODO: 나중에 실제 구현으로 교체한다.
# Codex가 만든 버그를 임시로 우회한다.
# Phase 3에서 실패해서 급하게 막았다.
# 테스트 통과를 위해 일단 고정값을 반환한다.
```

## Acceptance Rule
A code change is not acceptable if comments contradict behavior, hide incomplete work, or create false confidence.
