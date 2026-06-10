# Claude Code Global Research Kit

설치:

```bash
bash claude-code/install.sh
```

설치 위치:

```text
~/.claude/CLAUDE.md
~/.claude/agents/*.md
~/.claude/skills/*/SKILL.md
```

`CLAUDE.md`는 항상 로드됩니다. `agents`는 subagent 정의입니다. `skills`는 관련 작업일 때만 본문이 로드되어 세부 템플릿과 도메인 규칙을 필요할 때 적용합니다.

Sequential Thinking MCP와 Codex MCP 서버 자체는 별도로 설치되어 있어야 합니다. 이 키트는 Claude에게 해당 MCP들을 적극적으로 사용하라고 지시합니다.

## Final Update

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.

Includes `research-repo-design` skill and `research-repo-architect` agent. Use them before creating, reviewing, or refactoring AI/ML, hardware-backed, side-channel, simulation, or handoff-driven research experiment repositories.
