# Universal Research Agent Prompt Kit

**작성일**: 2026-05-28  
**최종 갱신**: 2026-05-28

Claude Code와 Codex를 연구자/개발자 작업 전반에 맞게 전역 설정하는 프롬프트·서브에이전트·스킬 패키지입니다.

이 키트의 목표는 다음입니다.

- 연구와 개발 모두에서 **근거 기반 작업**을 강제합니다.
- Claude Code는 `CLAUDE.md`, subagent, skill을 통해 작업을 라우팅합니다.
- Codex는 `AGENTS.md`, custom agent TOML, skill을 통해 작업을 라우팅합니다.
- 세부 템플릿과 도메인 규칙은 항상 로드하지 않고, **관련 작업이 들어왔을 때만 skill이 불러오도록** 구성합니다.
- Sequential Thinking MCP와 Codex MCP 적대적 리뷰를 적극적으로 사용하도록 지시합니다.
- placeholder, TODO, dummy, fallback, test-only hardcoding, fake-pass를 금지합니다.

## 빠른 설치

```bash
unzip universal_research_agent_prompt_kit.zip
cd universal_research_agent_prompt_kit
bash install_all.sh
```

설치 스크립트는 기존 전역 파일을 덮어쓰기 전에 `.bak.<timestamp>` 백업을 만듭니다.

## 폴더 구조

```text
universal_research_agent_prompt_kit/
├─ README.md
├─ install_all.sh
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

`CLAUDE.md`는 항상 로드됩니다. `agents`는 subagent 정의로 인식됩니다. `skills`는 이름/설명만 가볍게 노출되고, 관련 작업일 때 본문이 로드됩니다.

### Codex

```text
~/.codex/AGENTS.md
~/.codex/agents/*.toml
~/.agents/skills/*/SKILL.md
```

`AGENTS.md`는 Codex 시작 시 로드됩니다. `agents/*.toml`은 custom subagent 정의입니다. `~/.agents/skills`는 Codex의 사용자 skill 위치입니다.

## Sequential Thinking MCP

이 키트는 Sequential Thinking MCP가 이미 설치되어 있다고 가정하고, Claude Code와 Codex에게 다음 방식으로 사용하도록 지시합니다.

- 비단순 작업 시작 전
- 구현/실험/분석 방향을 정하기 전
- 결과를 acceptance 하기 전
- 오류 복구 또는 원인 분석 시

MCP 서버 자체를 설치하거나 설정하지는 않습니다. MCP 설정은 각자의 환경에 맞게 별도로 구성해야 합니다.

## Codex MCP 적대적 리뷰

Claude Code 지침은 중요한 작업 중간마다 Codex MCP를 적대적 리뷰어로 호출하도록 설계되어 있습니다.

권장 checkpoint:

1. Plan Review
2. First Slice Review
3. Pre-Test Review
4. Post-Result Review
5. Pre-Acceptance Review

Codex MCP가 없거나 실패하면 approval로 간주하지 않고, 실패를 기록한 뒤 더 작은 slice와 더 명확한 review packet으로 재시도하도록 지시합니다.

## GitHub에서 관리하는 방법

이 저장소는 prompt kit 원본으로 관리하세요.

- 지침을 수정하면 이 저장소의 파일을 수정합니다.
- 수정 후 `bash install_all.sh`로 전역 설정에 다시 설치합니다.
- 실제 연구/개발 프로젝트마다 별도 `CLAUDE.md`나 `AGENTS.md`를 둘 필요는 없습니다.
- 프로젝트별로 필요한 특수 규칙만 있다면 해당 프로젝트의 문서에 남기거나, 전역 skill에 추가하세요.

## 검증

설치 후 다음을 확인하세요.

```bash
bash verify_install.sh
```

Claude Code에서는 `/memory`, `/agents`, `/skills`로 로드 상태를 확인할 수 있습니다.

Codex에서는 새 세션에서 `loaded instructions` 또는 `available agents/skills`를 물어보면 됩니다.

## 중요 원칙

절대 다음을 acceptance 근거로 삼지 않습니다.

- “테스트 통과”라는 말만 있는 경우
- 로그가 없는 경우
- 부분 실험을 전체 성공처럼 말하는 경우
- TODO/placeholder/dummy/stub가 남은 경우
- fallback 또는 하드코딩으로 통과한 경우
- LLM 리뷰가 템플릿만 반복한 경우
- daemon restart로 문제가 사라진 것처럼 보이는 경우

승인은 오직 claim, artifact, deterministic evidence, adversarial review, documentation이 일치할 때만 가능합니다.
