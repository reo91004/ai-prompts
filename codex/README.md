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

역할을 고정할 때는 native spawn의 정확한 `agent_type`을 지정합니다. 같은 호출에서 역할·모델·추론 override를 지정할 때는 현재 Multi-Agent V2 full-history 모드가 그 호출을 거부하므로 `fork_turns="none"` 또는 제한된 양의 turn 수를 사용합니다. override가 없으면 필요한 문맥에 따라 `"all"`도 사용할 수 있습니다. 현재 런타임이 `agent_type`, `model`, `reasoning_effort`를 노출하지 않으면 `~/.agents/skills/resource-aware-orchestration/scripts/run_codex_agent.sh <role> <task>`를 사용합니다. 이 runner는 agent TOML의 모델·추론 강도·sandbox·developer instructions를 별도 `codex exec --ephemeral`에 명시하며, 네이티브 collaboration child와는 구분해 기록합니다.

opt-in 통합은 LazyCodex와 Ponytail을 설치할 수 있고, Sequential Thinking MCP는 profile과 무관하게 없을 때만 pin 버전으로 자동 등록됩니다. 설치기는 그 외의 사용자 MCP 등록을 수정하거나 삭제하지 않습니다.

## Portable harness

macOS, Linux, WSL을 지원하며 Native Windows와 Git Bash는 제외합니다. non-trivial 작업은 위임 트리거(구현 슬라이스·낯선 코드 탐색·큰 출력 격리·도메인 리뷰·material claim 수용·독립 병렬)를 먼저 찾아 적극 위임하고, 트리거가 없으면 main-only로 처리합니다. child 1개도 0개도 유효하며 강제 최소 인원은 없습니다. `max_threads = 6`은 목표가 아니라 ceiling이고 `max_depth = 1`입니다. writer는 shared worktree당 하나, heavy command는 한 번에 하나만 실행합니다. 큰 출력은 artifact에 두고 요약만 회수하며, 장기 실행 작업은 progress/checkpoint 계약으로 관리하고 경과 시간만으로 중단하지 않습니다.

Codex direct background terminal은 완료를 부모에게 push하지 않으므로 부모가 PID·로그를 반복 polling하지 않습니다. 명령이 확정된 긴 학습·합성·캡처는 `experiment_monitor`를 격리 runner로 실행합니다. 이 역할만 Luna/low와 `danger-full-access`를 사용해 실행·blocking wait·종료 evidence를 소유하며, 실험 설계·명령 생성·결과 해석·claim 수용·미지정 재시도는 하지 않습니다. 부모는 독립 작업 뒤 dependency boundary에서 runner session을 기다리고, wait timeout에는 재분석 없이 다시 기다립니다.

`config.toml.example`의 `max_threads = 6`, `max_depth = 1` harness 예시는 `codex/install.sh`가 사용자 `~/.codex/config.toml`에 자동 병합하지 않습니다. 다만 통합 단계는 두 가지를 수렴시킵니다: ultra 외 profile에서 LazyCodex를 버전 무관 비활성화(`[plugins."omo@sisyphuslabs"] enabled = false`)하고, `agents.max_threads`가 6을 넘으면(LazyCodex 잔재) 6으로 낮춥니다. 키트 소유가 아닌 ponytail marketplace/plugin은 보존합니다. `resource-aware-orchestration` detector는 각 spawn wave 전에 실행하고, 지속적인 압박 신호가 확인될 때만 slot을 낮추며 감지 실패는 자원 부족으로 해석하지 않습니다.

`review-budget`은 변경 범위별 최소 deterministic validation을 먼저 정하고, 필요한 경우에만 semantic reviewer 한 명과 기본 1회의 delta review를 허용합니다. installer regression과 integration migration은 해당 경로가 바뀐 경우에만 실행합니다. `evidence-gate`가 evidence와 claim scope의 기준이며 물리 capture에만 `hardware-capture-integrity`를 추가합니다.

저장소 검증:

```bash
bash scripts/validate_harness.sh
bash tests/test_resource_detector.sh
bash tests/test_codex_agent_runner.sh
```

CI workflow는 macOS·Ubuntu의 live detector를 실행하도록 구성했지만 remote run은 아직 확인되지 않았습니다. 현재 로컬 실측은 macOS이고 WSL은 fixture 근거만 있으므로 실제 WSL 호스트와 물리 장비 capture는 별도 실측이 필요합니다.

## 포함된 정책

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.

Includes `research-repo-design` skill and `research_repo_architect` agent. Use them before creating, reviewing, or refactoring AI/ML, hardware-backed, side-channel, simulation, or handoff-driven research experiment repositories.

Includes calibrated research-code guard policy. Adversarial review should require fixes for claim integrity, provenance, seed/config/run binding, synthetic/measured separation, fake-pass prevention, and user-data safety; production-only hardening stays optional unless production scope is requested.

Includes `planned-work` skill. Use it for multi-session, claim-bearing, or handover-driven work: it keeps a user-inspectable plan and evidence ledger under the project's `.plans/` — a machine-readable `ledger.json` (active work, status, constraints) plus a `plan.md` TODO checklist — without LazyCodex-style forced delegation or multi-lane review.
