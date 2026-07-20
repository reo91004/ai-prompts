# Claude Code Global Research Kit

설치:

```bash
bash claude-code/install.sh
```

플랫폼 설정만 설치하는 명령입니다. 저장소 루트의 `sh install.sh`는 선택한 profile로 상태를 수렴시킵니다: 기본(none)은 core 설치와 함께 kit-owned 통합 잔재를 정리하고, Ponytail은 `--integrations ponytail`(또는 `ultra`)로 opt-in합니다. user-owned plugin/marketplace는 보존하고 그 결과를 `integrations.state`에 기록합니다. LazyCodex는 Codex 전용이므로 Claude Code에는 설치하지 않습니다. Sequential Thinking MCP는 없을 때만 자동 등록되고, 그 외 사용자 MCP 등록은 수정·삭제하지 않습니다.

설치 위치:

```text
~/.claude/CLAUDE.md
~/.claude/agents/*.md
~/.claude/skills/*/SKILL.md
```

`CLAUDE.md`는 항상 로드됩니다. `agents`는 subagent 정의입니다. `skills`는 관련 작업일 때만 본문이 로드되어 세부 템플릿과 도메인 규칙을 필요할 때 적용합니다.

역할별 모델과 effort를 고정하려면 Agent 도구의 정확한 subagent type 또는 `@agent-name`을 사용합니다. `description` 기반 자동 선택은 휴리스틱이므로 고정 역할의 근거로 쓰지 않습니다. `CLAUDE_CODE_SUBAGENT_MODEL`과 `CLAUDE_CODE_EFFORT_LEVEL`이 설정되어 있으면 agent 정의를 바꿀 수 있으므로 task packet과 검증 evidence에 함께 기록합니다.

Sequential Thinking MCP는 설치기가 없을 때만 pin 버전으로 자동 등록하며 genuinely hard planning, 원인이 불명확한 debugging, 비싼 실험 설계, claim acceptance에서만 사용합니다. 필요하지만 사용할 수 없으면 성공으로 간주하지 않고 limitation을 기록합니다. Codex MCP는 이 harness의 필수 조건이 아니며 project overlay나 명시된 작업이 요구할 때만 사용합니다.

## Portable harness

macOS, Linux, WSL을 지원하며 Native Windows와 Git Bash는 제외합니다. non-trivial 작업은 위임 트리거(구현 슬라이스·낯선 코드 탐색·큰 출력 격리·도메인 리뷰·material claim 수용·독립 병렬)를 먼저 찾아 적극 위임하고, 트리거가 없으면 main-only로 처리합니다. child 1개도 0개도 유효하며 강제 최소 인원은 없습니다. 기본 thread 상한 6은 목표가 아니라 ceiling이고 depth는 1입니다. writer는 shared worktree당 하나, heavy command는 한 번에 하나만 실행합니다. 모든 child에서 `Agent` 도구를 금지합니다. 큰 출력은 artifact에 두고 요약만 회수하며, 장기 실행 작업은 progress/checkpoint 계약으로 관리하고 경과 시간만으로 중단하지 않습니다.

긴 학습·캡처는 Claude Code [`Monitor`](https://code.claude.com/docs/en/tools-reference#monitor-tool)를 우선 사용합니다. watcher는 routine progress를 로그에만 쓰고 완료·실패·권한 요청·확정된 무진행·자원/장비 비상·operator intervention만 모델에 전달합니다. 실행 중인 버전이 background subagent의 reliable completion semantics를 보장하지 않으면 `Monitor` 또는 foreground blocking을 사용하며 `/tasks`나 output file을 반복 polling하지 않습니다.

Fable은 main orchestrator 권장 모델일 뿐 강제되지 않습니다. 이 설치기는 Claude main model이나 사용자별 설정을 자동 변경하지 않습니다.

`resource-aware-orchestration`은 컴퓨터별 CPU·메모리·swap·PSI·cgroup 상태를 매 spawn wave 전에 측정합니다. `review-budget`은 변경 범위별 최소 deterministic validation을 먼저 정하고, 필요한 경우에만 semantic reviewer 한 명과 기본 1회의 targeted delta review를 허용합니다. installer regression과 integration migration은 해당 경로가 바뀐 경우에만 실행하며, 물리 capture가 있을 때만 `hardware-capture-integrity`를 사용합니다.

저장소 검증:

```bash
bash scripts/validate_harness.sh
bash tests/test_resource_detector.sh
bash tests/test_codex_agent_runner.sh
```

CI workflow는 macOS·Ubuntu의 live detector를 실행하도록 구성했지만 remote run은 아직 확인되지 않았습니다. 현재 로컬 실측은 macOS이고 WSL은 fixture 근거만 있으므로 실제 WSL 호스트와 물리 장비 capture는 별도 실측이 필요합니다.

## 포함된 정책

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.

Includes `research-repo-design` skill and `research-repo-architect` agent. Use them before creating, reviewing, or refactoring AI/ML, hardware-backed, side-channel, simulation, or handoff-driven research experiment repositories.

Includes calibrated research-code guard policy. Adversarial review should require fixes for claim integrity, provenance, seed/config/run binding, synthetic/measured separation, fake-pass prevention, and user-data safety; production-only hardening stays optional unless production scope is requested.

Includes `planned-work` skill. Use it for multi-session, claim-bearing, or handover-driven work: it keeps a user-inspectable plan and evidence ledger under the project's `.plans/` — a machine-readable `ledger.json` (active work, status, constraints) plus a `plan.md` TODO checklist — without LazyCodex-style forced delegation or multi-lane review.
