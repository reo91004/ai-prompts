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

Sequential Thinking MCP는 설치기가 없을 때만 pin 버전으로 자동 등록하며 genuinely hard planning, 원인이 불명확한 debugging, 비싼 실험 설계, claim acceptance에서만 사용합니다. 필요하지만 사용할 수 없으면 성공으로 간주하지 않고 limitation을 기록합니다. Codex MCP는 이 harness의 필수 조건이 아니며 project overlay나 명시된 작업이 요구할 때만 사용합니다.

## Portable harness

macOS, Linux, WSL을 지원하며 Native Windows와 Git Bash는 제외합니다. 작은 작업은 main-only입니다. child 수는 독립 산출물 수를 따르고 child 1개도 유효합니다. 기본 thread 상한 6은 목표가 아니라 ceiling이고 depth는 1입니다. writer는 shared worktree당 하나, heavy command는 한 번에 하나만 실행합니다. 모든 child에서 `Agent` 도구를 금지합니다. 장기 실행 작업은 progress/checkpoint 계약으로 관리하며 경과 시간만으로 중단하지 않습니다.

Fable은 main orchestrator 권장 모델일 뿐 강제되지 않습니다. `CLAUDE_CODE_SUBAGENT_MODEL`은 agent별 model을 덮어쓰므로 설정되어 있다면 검증 evidence에 기록해야 합니다. 이 설치기는 Claude main model이나 사용자별 설정을 자동 변경하지 않습니다.

`resource-aware-orchestration`은 컴퓨터별 CPU·메모리·swap·PSI·cgroup 상태를 매 spawn wave 전에 측정합니다. `review-budget`은 deterministic verifier 이후 한 semantic reviewer와 기본 1회의 targeted delta review를 관리하며, 물리 capture가 있을 때만 `hardware-capture-integrity`를 사용합니다.

저장소 검증:

```bash
bash scripts/validate_harness.sh
bash tests/test_resource_detector.sh
```

CI workflow는 macOS·Ubuntu의 live detector를 실행하도록 구성했지만 remote run은 아직 확인되지 않았습니다. 현재 로컬 실측은 macOS이고 WSL은 fixture 근거만 있으므로 실제 WSL 호스트와 물리 장비 capture는 별도 실측이 필요합니다.

## 포함된 정책

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.

Includes `research-repo-design` skill and `research-repo-architect` agent. Use them before creating, reviewing, or refactoring AI/ML, hardware-backed, side-channel, simulation, or handoff-driven research experiment repositories.

Includes calibrated research-code guard policy. Adversarial review should require fixes for claim integrity, provenance, seed/config/run binding, synthetic/measured separation, fake-pass prevention, and user-data safety; production-only hardening stays optional unless production scope is requested.
