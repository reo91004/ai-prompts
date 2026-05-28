# Codex Global Research Kit

설치:

```bash
bash codex/install.sh
```

설치 위치:

```text
~/.codex/AGENTS.md
~/.codex/agents/*.toml
~/.agents/skills/*/SKILL.md
```

Codex는 `AGENTS.md`를 전역 지침으로 읽고, `~/.codex/agents/*.toml`을 custom agent로 사용합니다. Codex skills는 `~/.agents/skills`에 설치되며, 관련 작업일 때 본문을 로드합니다.

Sequential Thinking MCP 자체는 별도 설치가 필요합니다.

## Final Update

Includes `code-comment-hygiene` skill and reviewer agent. Use it for stale comments, TODO/FIXME/HACK cleanup, and comment-code mismatch review.
