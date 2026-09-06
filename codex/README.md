# Codex

설치·갱신·검증·백업 정리는 저장소 루트의 [install.sh](../install.sh)를 사용합니다. 기본 설치는 MCP·Ponytail·Graphify·Headroom을 유지하며 자세한 옵션과 사용자 파일 보호 범위는 [공통 안내](../README.md)에 있습니다.

```bash
sh install.sh
sh install.sh --verify
```

[AGENTS.md](AGENTS.md)는 상시 판단 기준입니다. [agents/](agents/)의 16개 TOML은 역할별 모델·추론 강도·sandbox를 유지하며, 공통 [skills/](../skills/)는 `~/.agents/skills/`로 복사됩니다. 스킬 원본 공유가 agent 설정을 합치지는 않습니다.

현재 역할 설정은 `gpt-6-astra`이며 effort와 sandbox는 역할별로 다릅니다. 역할을 지정할 때는 실제 런타임의 선택 기능을 사용하고, 격리 runner가 필요하면 [플랫폼 실행 안내](../skills/resource-aware-orchestration/references/platform_dispatch.md)를 읽습니다. 요청한 설정과 실제 실행값을 구분합니다.

장기 실행은 [완료 기반 실행 안내](../skills/resource-aware-orchestration/references/long_runs.md)에 따라 명령·로그·체크포인트·종료 evidence를 관리합니다. `config.toml.example`은 thread/depth 상한 예시이며 사용자 설정을 일괄 덮어쓰는 정책이 아닙니다.
