# Claude Code

설치·갱신·검증·백업 정리는 저장소 루트의 [install.sh](../install.sh)를 사용합니다. 기본 설치는 MCP·Ponytail·Graphify·Headroom을 유지하며 자세한 옵션과 사용자 파일 보호 범위는 [공통 안내](../README.md)에 있습니다.

```bash
sh install.sh
sh install.sh --verify
```

[CLAUDE.md](CLAUDE.md)는 상시 판단 기준입니다. [agents/](agents/)의 16개 정의는 역할별 모델·effort·도구·권한을 유지하며, 공통 [skills/](../skills/)는 `~/.claude/skills/`로 복사됩니다. 스킬 원본 공유가 agent 설정을 합치지는 않습니다.

역할별 Opus/Sonnet과 도구 제한을 적용하고 실제 환경 override가 있으면 구분합니다. 모델이나 실행 방법의 상세는 [플랫폼 실행 안내](../skills/resource-aware-orchestration/references/platform_dispatch.md)를 필요한 때 읽습니다.

Codex와의 협력은 구체적인 질문·독립 산출물·유용한 검토가 있는 단계에서 사용하고, 같은 검토를 중복 승인으로 만들지 않습니다. 실험은 [실험 실행 안내](../skills/resource-aware-orchestration/references/experiment_runs.md)에 따라 세션과 분리해 실행하고, 새 세션에서도 끝날 때까지 기다리거나 결과를 확인합니다. 주 모델은 사용자가 선택하며 오케스트레이터 effort는 `/effort xhigh`로 맞춥니다. 돌파구가 필요하면 [토론 라운드](../skills/research-repo-protocol/SKILL.md#discussion-rounds)에서 `breakthrough-analyst`(Max)와 Codex `breakthrough_analyst`(Ultra)를 함께 씁니다.
