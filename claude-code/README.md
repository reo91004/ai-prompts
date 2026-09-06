# Claude Code

설치·갱신·검증·백업 정리는 저장소 루트의 [install.sh](../install.sh)를 사용합니다. 기본 설치는 MCP·Ponytail·Graphify·Headroom을 유지하며 자세한 옵션과 사용자 파일 보호 범위는 [공통 안내](../README.md)에 있습니다.

```bash
sh install.sh
sh install.sh --verify
```

[CLAUDE.md](CLAUDE.md)는 상시 판단 기준입니다. [agents/](agents/)의 15개 정의는 역할별 모델·effort·도구·권한을 유지하며, 공통 [skills/](../skills/)는 `~/.claude/skills/`로 복사됩니다. 스킬 원본 공유가 agent 설정을 합치지는 않습니다.

역할별 Opus/Sonnet과 도구 제한을 적용하고 실제 환경 override가 있으면 구분합니다. 모델이나 실행 방법의 상세는 [플랫폼 실행 안내](../skills/resource-aware-orchestration/references/platform_dispatch.md)를 필요한 때 읽습니다.

Codex와의 협력은 구체적인 질문·독립 산출물·유용한 검토가 있는 단계에서 사용하고, 같은 검토를 중복 승인으로 만들지 않습니다. 장기 실행은 [완료 기반 실행 안내](../skills/resource-aware-orchestration/references/long_runs.md)에 따라 로그·체크포인트·종료 evidence를 관리합니다. 주 모델 설정은 사용자가 선택합니다.
