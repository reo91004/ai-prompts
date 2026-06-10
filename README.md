# Universal Research Agent Prompt Kit

**작성일**: 2026-05-28  
**최종 갱신**: 2026-06-10

Claude Code와 Codex를 연구자/개발자 작업 전반에 맞게 전역 설정하는 프롬프트·서브에이전트·스킬 패키지입니다.

## 핵심 목표

- 연구와 개발 모두에서 **근거 기반 작업**을 강제합니다.
- Claude Code는 `CLAUDE.md`, subagent, skill을 통해 작업을 라우팅합니다.
- Codex는 `AGENTS.md`, custom agent TOML, skill을 통해 작업을 라우팅합니다.
- 세부 템플릿과 도메인 규칙은 항상 로드하지 않고, 관련 작업이 들어왔을 때만 skill이 불러오도록 구성합니다.
- Sequential Thinking MCP와 Codex MCP 적대적 리뷰를 적극적으로 사용하도록 지시합니다.
- placeholder, TODO, FIXME, dummy, fallback, test-only hardcoding, fake-pass를 금지합니다.
- **기존 주석이 현재 코드와 맞지 않으면 수정하거나 삭제**하도록 강제합니다.
- 새 연구 실험 레포를 만들거나 리팩토링할 때 **하드웨어 기반 논문 아이디어 검증용 구조**를 선택하도록 `research-repo-design` skill을 제공합니다.

## 빠른 설치

```bash
unzip universal_research_agent_prompt_kit_final.zip
cd universal_research_agent_prompt_kit_final
bash install_all.sh
```

설치 스크립트는 루트 설정 디렉터리를 보존하고, 이 키트가 관리하는 agents/skills 영역만 백업 후 깨끗하게 재설치합니다.

보존:

```text
~/.claude/
~/.codex/
~/.agents/
```

백업 후 재생성:

```text
~/.claude/agents
~/.claude/skills
~/.codex/agents
~/.agents/skills
```

덮어쓰기 전 파일 백업:

```text
~/.claude/CLAUDE.md.bak.<timestamp>
~/.codex/AGENTS.md.bak.<timestamp>
~/.config/git/ignore.bak.<timestamp>
```

`~/.agents/skills`는 이 키트 전용 관리 영역으로 취급합니다. 개인 스킬을 같은 위치에 둘 경우 기본 설치가 백업 후 제거합니다.

## 백업 정리

설치가 만든 백업을 확인하려면 dry-run으로 실행합니다.

```bash
bash cleanup_backups.sh
```

실제로 삭제하려면 명시적으로 `--delete`를 붙입니다.

```bash
bash cleanup_backups.sh --delete
```

## 폴더 구조

```text
universal_research_agent_prompt_kit_final/
├─ README.md
├─ install_all.sh
├─ cleanup_backups.sh
├─ verify_install.sh
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

## 새로 보강된 주석 정책

이 최종본은 다음을 강제합니다.

- 주석은 현재 동작만 설명해야 합니다.
- 오래된 버그 이력, phase 이력, 임시 수리 이력, 에이전트가 고쳤다는 설명은 소스 주석에 남기지 않습니다.
- 기존 주석이 코드와 불일치하면 수정하거나 삭제합니다.
- TODO/FIXME/HACK/temporary 주석은 accepted code에 남기지 않습니다.
- 미완료 작업은 carry-over 문서나 issue tracker로 옮깁니다.
- 주석은 구현 증거가 아닙니다. 실제 코드, 로그, 테스트, 데이터로 검증해야 합니다.

## 연구 실험 레포 설계 정책

새 연구 프로젝트, 하드웨어 실측 레포, side-channel/FPGA/embedded 실험 레포, handoff 기반 구조 정리 요청에서는 `research-repo-design` skill을 사용합니다.

이 skill은 다음 방향을 강제합니다.

- `scripts/`는 번호가 붙은 실험 프로토콜로 둡니다.
- 짧은 root package는 라벨, 캡처, 세그먼트, 분석 같은 작은 재사용 함수만 담습니다.
- `target/`은 측정 대상, firmware, host wrapper, vendor 원본을 담습니다.
- `runs/`는 실험 산출물을 run 단위로 완결적으로 보관합니다.
- `docs/`에는 현재 source of truth만 두고 오래된 계획은 archive로 보냅니다.
- generic framework, plugin registry, config schema migration, mega CLI, 과도한 추상화를 피합니다.

## Sequential Thinking MCP

이 키트는 Sequential Thinking MCP가 이미 설치되어 있다고 가정하고, Claude Code와 Codex에게 비단순 작업에서 적극 사용하도록 지시합니다. MCP 서버 자체를 설치하거나 설정하지는 않습니다.

## Codex MCP 적대적 리뷰

Claude Code 지침은 중요한 작업 중간마다 Codex MCP를 적대적 리뷰어로 호출하도록 설계되어 있습니다.

권장 checkpoint:

1. Plan Review
2. First Slice Review
3. Pre-Test Review
4. Post-Result Review
5. Pre-Acceptance Review

Codex MCP가 없거나 실패하면 approval로 간주하지 않고, 실패를 기록한 뒤 더 작은 slice와 더 명확한 review packet으로 재시도하도록 지시합니다.

## 검증

설치 후 다음을 확인하세요.

```bash
bash verify_install.sh
```

## 중요 원칙

절대 다음을 acceptance 근거로 삼지 않습니다.

- “테스트 통과”라는 말만 있는 경우
- 로그가 없는 경우
- 부분 실험을 전체 성공처럼 말하는 경우
- TODO/placeholder/dummy/stub가 남은 경우
- stale comment가 남은 경우
- fallback 또는 하드코딩으로 통과한 경우
- LLM 리뷰가 템플릿만 반복한 경우
- daemon restart로 문제가 사라진 것처럼 보이는 경우

승인은 오직 claim, artifact, deterministic evidence, adversarial review, current comments/documentation, documentation trail이 일치할 때만 가능합니다.
