# Claude Code

[Crucible 공통 스킬](../skills/crucible/SKILL.md)은 별도 연구 루프 엔진을 호출합니다. `~/reo/crucible` 또는 `CRUCIBLE_ROOT` 경로의 CLI를 사용하며, 연구 상태는 각 프로젝트의 `.crucible/`에 유지합니다. OpenCode와 동일한 실행·복구·기록을 재사용합니다.

한 번 실험·평가기·모델·예산을 준비하고 시작하면 등록된 사건에서 자동 토론합니다. `/crucible debate <질문>`은 즉시 수동 토론을 요청하는 경로이며, 실험을 실행하거나 진행 중인 루프의 다음 결정을 바꾸지 않습니다. 실제 명령과 설정은 스킬에 따라 에이전트가 작성할 수 있습니다. 자세한 사용법은 [Crucible 한국어 안내](https://github.com/reo91004/Crucible/blob/main/docs/README.ko.md)에 있습니다.

설치·갱신·검증·백업 정리는 저장소 루트의 [install.sh](../install.sh)를 사용합니다. 기본 설치는 MCP·Ponytail·Graphify·Headroom을 유지하며 자세한 옵션과 사용자 파일 보호 범위는 [공통 안내](../README.md)에 있습니다.

```bash
sh install.sh
sh install.sh --verify
```

[CLAUDE.md](CLAUDE.md)는 상시 판단 기준입니다. [agents/](agents/)의 15개 정의는 역할별 모델·effort·도구·권한을 유지하며, 공통 [skills/](../skills/)는 `~/.claude/skills/`로 복사됩니다. 스킬 원본 공유가 agent 설정을 합치지는 않습니다.

역할별 Opus/Sonnet과 도구 제한을 적용하고 실제 환경 override가 있으면 구분합니다. 모델이나 실행 방법의 상세는 [플랫폼 실행 안내](../skills/resource-aware-orchestration/references/platform_dispatch.md)를 필요한 때 읽습니다.

Codex와의 협력은 구체적인 질문·독립 산출물·유용한 검토가 있는 단계에서 사용하고, 같은 검토를 중복 승인으로 만들지 않습니다. 장기 실행은 [완료 기반 실행 안내](../skills/resource-aware-orchestration/references/long_runs.md)에 따라 로그·체크포인트·종료 evidence를 관리합니다. 주 모델 설정은 사용자가 선택합니다.
