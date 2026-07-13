# Codex Global Research Kit

설치:

```bash
bash codex/install.sh
```

플랫폼 설정만 설치하는 명령입니다. 저장소 루트의 `sh install.sh`는 선택한 profile로 상태를 수렴시킵니다: 기본(none)은 core 설치와 함께 kit-pinned LazyCodex(4.17.0)를 비활성화하고 kit-owned Ponytail을 제거하며, Ponytail은 `--integrations ponytail`, LazyCodex까지는 `--integrations ultra`로 opt-in합니다. user-owned plugin/marketplace는 보존되고 결과는 `integrations.state`에 호스트별로 기록됩니다.

설치 위치:

```text
~/.codex/AGENTS.md
~/.codex/agents/*.toml
~/.agents/skills/*/SKILL.md
```

Codex는 `AGENTS.md`를 전역 지침으로 읽고, `~/.codex/agents/*.toml`을 custom agent로 사용합니다. Codex skills는 `~/.agents/skills`에 설치되며, 관련 작업일 때 본문을 로드합니다.

opt-in 통합은 LazyCodex와 Ponytail을 설치할 수 있고, Sequential Thinking MCP는 profile과 무관하게 없을 때만 pin 버전으로 자동 등록됩니다. 설치기는 그 외의 사용자 MCP 등록을 수정하거나 삭제하지 않습니다.

## Portable harness

macOS, Linux, WSL을 지원하며 Native Windows와 Git Bash는 제외합니다. 작은 작업은 main-only입니다. child 수는 독립 산출물 수를 따르고 child 1개도 유효합니다. `max_threads = 6`은 목표가 아니라 ceiling이고 `max_depth = 1`입니다. writer는 shared worktree당 하나, heavy command는 한 번에 하나만 실행합니다. 장기 실행 작업은 progress/checkpoint 계약으로 관리하며 경과 시간만으로 중단하지 않습니다.

`config.toml.example`의 `max_threads = 6`, `max_depth = 1` harness 예시는 `codex/install.sh`가 사용자 `~/.codex/config.toml`에 자동 병합하지 않습니다. 다만 통합 단계는 두 가지를 수렴시킵니다: ultra 외 profile에서 LazyCodex를 버전 무관 비활성화(`[plugins."omo@sisyphuslabs"] enabled = false`)하고, `agents.max_threads`가 6을 넘으면(LazyCodex 잔재) 6으로 낮춥니다. 키트 소유가 아닌 ponytail marketplace/plugin은 보존합니다. `resource-aware-orchestration` detector는 각 spawn wave 전에 실행하고, 지속적인 압박 신호가 확인될 때만 slot을 낮추며 감지 실패는 자원 부족으로 해석하지 않습니다.

`review-budget`은 deterministic verifier 다음에 한 semantic reviewer를 배치하고 기본 2회 이내의 최초/delta review를 관리합니다. `evidence-gate`가 evidence와 claim scope의 기준이며 물리 capture에만 `hardware-capture-integrity`를 추가합니다.

저장소 검증:

```bash
bash scripts/validate_harness.sh
bash tests/test_resource_detector.sh
```

CI workflow는 macOS·Ubuntu의 live detector를 실행하도록 구성했지만 remote run은 아직 확인되지 않았습니다. 현재 로컬 실측은 macOS이고 WSL은 fixture 근거만 있으므로 실제 WSL 호스트와 물리 장비 capture는 별도 실측이 필요합니다.

## 포함된 정책

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.

Includes `research-repo-design` skill and `research_repo_architect` agent. Use them before creating, reviewing, or refactoring AI/ML, hardware-backed, side-channel, simulation, or handoff-driven research experiment repositories.

Includes calibrated research-code guard policy. Adversarial review should require fixes for claim integrity, provenance, seed/config/run binding, synthetic/measured separation, fake-pass prevention, and user-data safety; production-only hardening stays optional unless production scope is requested.

Includes `planned-work` skill. Use it for multi-session, claim-bearing, or handover-driven work: it keeps the user-inspectable plan and evidence ledger under the project's `.plans/` without LazyCodex-style forced delegation or multi-lane review.
