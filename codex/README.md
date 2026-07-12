# Codex Global Research Kit

설치:

```bash
bash codex/install.sh
```

플랫폼 설정만 설치하는 명령입니다. LazyCodex와 Ponytail까지 한 번에 설치하려면 저장소 루트에서 `bash install_all.sh`를 실행합니다.

설치 위치:

```text
~/.codex/AGENTS.md
~/.codex/agents/*.toml
~/.agents/skills/*/SKILL.md
```

Codex는 `AGENTS.md`를 전역 지침으로 읽고, `~/.codex/agents/*.toml`을 custom agent로 사용합니다. Codex skills는 `~/.agents/skills`에 설치되며, 관련 작업일 때 본문을 로드합니다.

루트 통합 설치는 LazyCodex와 Ponytail을 설치하지만 Sequential Thinking MCP 자체는 별도 설치가 필요합니다.

## Portable harness

macOS, Linux, WSL을 지원하며 Native Windows와 Git Bash는 제외합니다. 작은 작업은 main-only입니다. 위임하면 비중복 child를 최소 2개 사용하고 detector가 동시성 1을 반환하면 순차 실행합니다. 기본 thread 상한은 6, depth는 1이며 writer와 heavy command는 각각 하나만 동시에 실행합니다.

`config.toml.example`의 `max_threads = 6`, `max_depth = 1` harness 예시는 `codex/install.sh`가 사용자 `~/.codex/config.toml`에 자동 병합하지 않습니다. 다만 루트 `install_all.sh`는 승인된 LazyCodex·Ponytail plugin/marketplace 등록과 기존 `arxiv`, `semantic-scholar`, `semantic_scholar` MCP 제거를 Codex CLI로 수행할 수 있으므로 해당 사용자 설정은 변경될 수 있습니다. `resource-aware-orchestration` detector는 각 spawn wave 전에 실행하고 컴퓨터별 CPU·메모리·swap·PSI·cgroup 상태에 따라 동시성을 낮춥니다.

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
