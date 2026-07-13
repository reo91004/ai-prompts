# Universal Research Agent Prompt Kit

**작성일**: 2026-05-28  
**최종 갱신**: 2026-07-13

Claude Code와 Codex를 연구자/개발자 작업 전반에 맞게 전역 설정하는 프롬프트·서브에이전트·스킬 패키지입니다.

## 핵심 목표

- 연구와 개발 모두에서 **근거 기반 작업**을 강제합니다.
- Claude Code는 `CLAUDE.md`, subagent, skill을 통해 작업을 라우팅합니다.
- Codex는 `AGENTS.md`, custom agent TOML, skill을 통해 작업을 라우팅합니다.
- 세부 템플릿과 도메인 규칙은 항상 로드하지 않고, 관련 작업이 들어왔을 때만 skill이 불러오도록 구성합니다.
- 어려운 계획·불명확한 디버깅·비싼 실험 설계·claim acceptance에서만 Sequential Thinking MCP를 사용합니다.
- 자원 상태에 맞춰 child 동시성을 조절하고 deterministic 검증과 semantic review를 분리합니다.
- placeholder, TODO, FIXME, dummy, fallback, test-only hardcoding, fake-pass를 금지합니다.
- 연구용 코드에서는 연구 무결성 가드와 프로덕션 방어 가드를 분리합니다.
- **기존 주석이 현재 코드와 맞지 않으면 수정하거나 삭제**하도록 강제합니다.
- 새 연구 실험 레포를 만들거나 리팩토링할 때 **AI/ML, 하드웨어, 부채널, 시뮬레이션 논문 아이디어 검증용 구조**를 선택하도록 `research-repo-design` skill과 전용 repository architect agent를 제공합니다.

## 빠른 설치

```bash
unzip universal_research_agent_prompt_kit_final.zip
cd universal_research_agent_prompt_kit_final
sh install.sh
```

`install.sh`는 POSIX sh bootstrap이라 `/bin/sh`가 dash인 Ubuntu에서도 그대로 실행됩니다. 내부 구현은 macOS 기본 Bash 3.2, Linux, WSL 호환 Bash입니다. Native Windows와 Git Bash는 지원 범위가 아닙니다.

기본 설치는 **core prompts/agents/skills만** 설치합니다. 외부 플러그인은 opt-in입니다.

```bash
sh install.sh                          # core만 (기본)
sh install.sh --integrations ponytail  # core + Ponytail
sh install.sh --integrations ultra     # core + Ponytail + LazyCodex 워크플로
```

LazyCodex의 고강도 다중 리뷰 워크플로는 이 키트의 review-budget 정책과 충돌하므로 명시적인 `ultra` 프로필에서만 설치합니다. 통합 설치에는 Node.js와 `git`, 네트워크 연결이 필요하고 LazyCodex에는 `npx`가 추가로 필요합니다. `UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1`은 프로필과 무관하게 통합을 생략합니다.

외부 코드는 설치 시점의 가변 `latest`나 기본 브랜치를 바로 실행하지 않습니다. LazyCodex는 검증된 `4.17.0` npm 릴리스로, Ponytail은 `4.8.4` 릴리스 커밋 `bc9ee949d5f439e8b9f3bb92c6d6d3d1e6ebd324`로 고정합니다.

설치 스크립트는 기존 설정과 agents/skills 디렉터리를 전용 상태 디렉터리에 백업한 뒤, ownership manifest에 기록된 키트 소유 항목만 교체합니다. LazyCodex, Ponytail, 개인 스킬처럼 다른 이름을 사용하는 제3자 항목은 삭제하지 않습니다. 키트 소유 항목과 이름이 같은 파일이나 디렉터리는 백업 후 키트 버전으로 교체합니다. 사용자가 직접 등록한 MCP 서버는 어떤 프로필에서도 조회·수정·삭제하지 않으며, 사용자 소유의 ponytail marketplace가 이미 있으면 키트는 해당 호스트의 Ponytail 관리를 건너뛰고 보존합니다.

설치 전체는 하나의 트랜잭션입니다. `umask 077`로 상태 디렉터리를 보호하고, 동시 설치를 lock으로 차단하며, 모든 변경을 journal에 기록해 어느 단계에서 실패하든 이전 단계까지의 변경을 자동으로 원상 복구합니다. gitignore managed block은 BEGIN/END marker 쌍을 검증한 뒤에만 교체합니다.

보존:

```text
~/.claude/
~/.codex/
~/.agents/
```

백업 후 키트 항목 갱신:

```text
~/.claude/agents
~/.claude/skills
~/.codex/agents
~/.agents/skills
```

설치 스냅샷과 소유권 기록:

```text
~/.universal-research-agent-kit/backups/run.<timestamp>.<unique>/
~/.universal-research-agent-kit/manifests/
~/.universal-research-agent-kit/sources/ponytail-<revision>/
~/.universal-research-agent-kit/marketplaces/ponytail-<revision>/
```

`~/.agents/skills`, `~/.codex/agents`, `~/.claude/skills`, `~/.claude/agents`는 다른 플러그인과 공유할 수 있습니다. 설치 검증은 키트의 필수 항목만 확인하며, 그 밖의 항목은 공존 대상으로 허용합니다.

## 백업 정리

키트 전용 상태 디렉터리에 있는 설치 스냅샷만 삭제합니다. 다른 프로그램이나 사용자가 만든 `*.bak.*` 파일은 건드리지 않으며 ownership manifest는 유지합니다.

```bash
bash cleanup_backups.sh
```

## 폴더 구조

```text
universal_research_agent_prompt_kit_final/
├─ README.md
├─ install.sh
├─ install_all.sh
├─ install_integrations.sh
├─ cleanup_backups.sh
├─ verify_install.sh
├─ scripts/validate_harness.sh
├─ tests/
│  ├─ test_resource_detector.sh
│  ├─ test_install_regression.sh
│  └─ fixtures/resources/
├─ lib/install_common.sh
├─ global_research_agents.gitignore
├─ .gitignore
├─ claude-code/
│  ├─ CLAUDE.md
│  ├─ install.sh
│  ├─ README.md
│  ├─ agents/*.md
│  └─ skills/*/SKILL.md
└─ codex/
   ├─ AGENTS.md
   ├─ install.sh
   ├─ README.md
   ├─ agents/*.toml
   └─ skills/*/SKILL.md
```

## 실제 설치 위치

### Claude Code

```text
~/.claude/CLAUDE.md
~/.claude/agents/*.md
~/.claude/skills/*/SKILL.md
```

### Codex

```text
~/.codex/AGENTS.md
~/.codex/agents/*.toml
~/.agents/skills/*/SKILL.md
```

## 자동 로드와 온디맨드 로드

항상 로드되는 것은 전역 지침 파일입니다.

- Claude Code: `~/.claude/CLAUDE.md`
- Codex: `~/.codex/AGENTS.md`

Subagent와 skill은 도구가 인식할 수 있는 위치에 설치됩니다. Skill 본문과 reference/template은 관련 작업일 때만 읽도록 지침화되어 있습니다.

## 자원 인식형 오케스트레이션

정책은 `Global Core → Domain Skill → Project Overlay` 순서로 적용됩니다. 작은 로컬 작업은 main agent가 단독 처리합니다. child 수는 독립 산출물 수를 따르며 **child 1개도 유효합니다** — 최소 인원을 채우기 위해 작업을 쪼개지 않습니다. 감지된 slot은 목표가 아니라 상한이고, child의 nested delegation은 금지됩니다(`max_depth = 1`).

resource detector는 macOS의 `sysctl`, `memory_pressure`, `vm_stat`, Linux/WSL의 `/proc`, PSI, cgroup v2 신호를 읽습니다. Linux에서는 현재 process의 cgroup v2 경로와 mount root를 해석하고 그 경로부터 mount root까지 가장 엄격한 memory, CPU, cpuset, OOM 제한을 적용합니다. `agent_slots`는 절대 메모리 headroom(가용 2GiB당 slot 1개, 1–6 clamp)과 CPU 한도, `HARNESS_MAX_THREADS`, `HARNESS_TASK_CAP`의 최솟값이며 기본 상한은 6입니다.

신호는 등급으로 구분합니다. low swap이나 낮은 가용 비율은 `warnings`로만 기록하고 slot을 줄이지 않습니다. swapout 증가나 critical PSI는 `RESOURCE_CONSTRAINED`로 slot을 한 단계 줄이고 heavy 작업을 보류하며, OOM 증가만 slot을 1로 강제합니다. 감지 실패는 `RESOURCE_UNKNOWN`으로 자원 부족과 구분됩니다 — 이때 `agent_slots`는 설정된 상한을 유지하고 새 GPU/장비 작업만 보류합니다. 600초를 넘긴 snapshot은 `RESOURCE_STALE`로 재측정을 요구합니다. 새 측정 결과는 새 spawn에만 적용되고 이미 정상 실행 중인 작업을 소급 중단하지 않습니다. writer slot은 shared worktree당 하나입니다. Linux snapshot은 `--system-root`로 read-only replay할 수 있습니다.

장기 실행 명령은 progress probe, checkpoint 경로, resume/graceful-cancel/cleanup 절차를 선언하고, 경과 시간이나 mailbox 응답 지연만으로는 절대 중단하지 않습니다.

[`codex/config.toml.example`](codex/config.toml.example)은 참고용입니다. 설치기는 기존 `~/.codex/config.toml`에 이 설정을 자동 병합하지 않습니다. 컴퓨터별 실제 CPU·메모리·cgroup 제한이 다르므로 detector를 각 spawn wave 전에 다시 실행해야 합니다.

Claude에서는 Fable을 main orchestrator 권장 모델로만 문서화하며 강제하지 않습니다. `CLAUDE_CODE_SUBAGENT_MODEL`이 설정되면 agent별 모델 선택을 덮어쓰므로 검증 기록에 해당 환경 변수를 남겨야 합니다.

## 새로 보강된 주석 정책

이 최종본은 다음을 강제합니다.

- 주석은 현재 동작만 설명해야 합니다.
- 오래된 버그 이력, phase 이력, 임시 수리 이력, 에이전트가 고쳤다는 설명은 소스 주석에 남기지 않습니다.
- 기존 주석이 코드와 불일치하면 수정하거나 삭제합니다.
- TODO/FIXME/HACK/temporary 주석은 accepted code에 남기지 않습니다.
- 미완료 작업은 carry-over 문서나 issue tracker로 옮깁니다.
- 주석은 구현 증거가 아닙니다. 실제 코드, 로그, 테스트, 데이터로 검증해야 합니다.

## 연구 실험 레포 설계 정책

새 연구 프로젝트, AI/ML 실험 레포, 하드웨어 실측 레포, side-channel/FPGA/embedded 실험 레포, 시뮬레이션 레포, handoff 기반 구조 정리 요청에서는 `research-repo-design` skill과 repository architect agent를 사용합니다.

이 skill은 다음 방향을 강제합니다.

- `scripts/`는 번호가 붙은 실험 프로토콜로 둡니다.
- 짧은 root package는 라벨, 캡처, 세그먼트, 분석 같은 작은 재사용 함수만 담습니다.
- 프로젝트 중심축을 먼저 고릅니다. 하드웨어/부채널은 `target/`, AI/ML은 `data/`와 model/training/evaluation, 시뮬레이션은 simulate/eval 흐름이 중심입니다.
- `runs/`는 실험 산출물을 run 단위로 완결적으로 보관합니다.
- `docs/`에는 현재 source of truth만 두고 오래된 계획은 archive로 보냅니다.
- generic framework, plugin registry, config schema migration, mega CLI, 과도한 추상화를 피합니다.

## Sequential Thinking MCP

이 키트는 Sequential Thinking MCP가 이미 설치되어 있다고 가정합니다. genuinely hard planning, 원인이 불명확한 debugging, 비싼 실험 설계, claim acceptance에서만 사용하며 MCP 부재를 성공으로 가장하지 않습니다. LazyCodex와 Ponytail은 opt-in 통합 대상이고 Sequential Thinking MCP 같은 기타 MCP 서버는 별도로 관리합니다. 키트는 기존 사용자 MCP 등록(`arxiv`, `semantic-scholar`, Zotero 등)을 조회하거나 제거하지 않습니다.

## Review와 evidence 계약

deterministic verifier가 먼저 통과한 뒤 필요한 경우에만 semantic reviewer를 한 명 사용합니다. 기본 review는 최초 1회와 변경 delta에 대한 targeted re-review 1회까지입니다. 세 번째 review는 새 blocker, scope/criterion 변경, 사용자 요청이 있을 때만 허용합니다. `Optional Hardening`만 남으면 종료합니다.

Evidence에는 origin, purpose, blinding, measurement scope, claim scope를 기록합니다. Diagnostic 결과는 claim-bearing 결과와 분리하며 evidence scope를 넘는 claim은 승인하지 않습니다. 물리 장비 capture가 포함된 경우에만 `hardware-capture-integrity` skill을 함께 사용하고 장비별 수치·attempt 한도는 project config/overlay에 둡니다.

RESOURCE 오류나 검증 실패는 해당 단계와 종속 단계, 최종 acceptance를 차단하지만 무관한 분석과 이미 생성된 evidence 보존은 계속할 수 있습니다. scoped retry 후에도 전체 목표가 불가능할 때만 task 전체를 `BLOCKED`로 판정합니다.

## 연구용 코드 가드 철학

적대적 리뷰는 논리 오류, 증거 부족, 재현성 붕괴, overclaim, fake-pass를 잡는 데 사용합니다. 다만 연구용 실험 코드를 프로덕션 서비스처럼 만들기 위한 방어 코드는 기본 acceptance blocker로 보지 않습니다.

유지해야 하는 것은 연구 무결성 가드입니다.

- synthetic evidence와 measured evidence 분리
- dataset/trace/model/target/bitstream/config/seed/commit SHA/run ID provenance
- missing artifact, fake metric, silent fallback 차단
- `claim_scope` 기록과 논문 주장 범위 제한
- 사용자 설정이나 데이터를 삭제·덮어쓰는 작업의 whitelist, backup, dry-run, fail-fast

반대로 내부 연구 helper의 과도한 dtype/shape 검증, 중복 검증, DoS/resource cap, TOCTOU 방어, 복잡한 exception hierarchy, generic schema/registry/framework machinery는 사용자가 production scope를 요구하지 않는 한 선택적 하드닝으로 둡니다.

이 레포의 설치·검증·정리 스크립트에 있는 `set -euo pipefail`, ownership manifest, 전용 백업 경계, symlink 거부, `exit 1`은 유지합니다. 이 스크립트들은 홈 설정과 백업을 다루므로 사용자 데이터 보호 장치가 필요합니다.

## 검증

저장소 계약과 설치 결과를 각각 확인합니다.

```bash
bash scripts/validate_harness.sh
bash tests/test_resource_detector.sh
bash tests/test_install_regression.sh
bash verify_install.sh
```

CI workflow는 macOS와 Ubuntu의 live detector 및 공통 회귀 검사를 실행하도록 구성되어 있지만, 이 변경의 remote CI 실행 결과는 아직 확인되지 않았습니다. 현재 로컬 실측은 macOS에 한정되고 WSL은 fixture로 detector 경로만 검증합니다. 실제 WSL runtime, 실제 hardware capture, 호스트별 최대 부하 성능은 별도 검증이 필요합니다.

### 릴리스 전 수동 행동 체크리스트

기계 검증(detector 신호 등급, low-swap 비직렬화, RESOURCE_UNKNOWN, 설치 롤백)은 위 테스트가 자동으로 다룹니다. 다음 LLM 행동 시나리오는 릴리스 전에 실제 세션에서 수동으로 확인하고, remote CI green과 함께 release blocker로 취급합니다.

| 시나리오                           | 기대 동작                                  |
| ---------------------------------- | ------------------------------------------ |
| README 한 문장 수정                | main-only, child 0                         |
| 단일 shell bug 수정                | writer 1, 직접 테스트, reviewer 0–1        |
| AI/ML metric 변경                  | 구현 + 통계/ML reviewer만                  |
| SCA claim 변경                     | SCA reviewer와 evidence gate               |
| 장시간 무출력 테스트               | elapsed time만으로 중단하지 않음           |
| 외부 plugin policy 충돌            | 키트 review/delegation budget이 우선       |

## 중요 원칙

절대 다음을 acceptance 근거로 삼지 않습니다.

- “테스트 통과”라는 말만 있는 경우
- 로그가 없는 경우
- 부분 실험을 전체 성공처럼 말하는 경우
- TODO/placeholder/dummy/stub가 남은 경우
- stale comment가 남은 경우
- fallback 또는 하드코딩으로 통과한 경우
- 연구 무결성 가드가 필요한데 선택적 하드닝처럼 무시한 경우
- LLM 리뷰가 템플릿만 반복한 경우
- daemon restart로 문제가 사라진 것처럼 보이는 경우

승인은 오직 claim, artifact, deterministic evidence, adversarial review, current comments/documentation, documentation trail이 일치할 때만 가능합니다.
