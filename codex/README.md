# Codex

설치·갱신·검증·백업 정리는 저장소 루트의 [install.sh](../install.sh)를 사용합니다. 기본 설치는 MCP·Ponytail·Graphify·Headroom을 유지하며 자세한 옵션과 사용자 파일 보호 범위는 [공통 안내](../README.md)에 있습니다.

```bash
sh install.sh
sh install.sh --verify
```

[AGENTS.md](AGENTS.md)는 상시 판단 기준입니다. [agents/](agents/)의 17개 TOML은 역할별 모델·추론 강도·sandbox를 유지하며, 공통 [skills/](../skills/)는 `~/.agents/skills/`로 복사됩니다. 스킬 원본 공유가 agent 설정을 합치지는 않습니다.

오케스트레이터 추론 강도는 설치 때 `model_reasoning_effort = "xhigh"`로 맞춥니다. 역할 설정은 `gpt-6-astra`이며 effort와 sandbox는 역할별로 다르고, [토론 라운드](../skills/research-repo-protocol/SKILL.md#discussion-rounds)의 `breakthrough_analyst`만 `ultra`를 씁니다. 역할을 지정할 때는 실제 런타임의 선택 기능을 사용하고, 격리 runner가 필요하면 [플랫폼 실행 안내](../skills/resource-aware-orchestration/references/platform_dispatch.md)를 읽습니다. 요청한 설정과 실제 실행값을 구분합니다.

실험은 [실험 실행 안내](../skills/resource-aware-orchestration/references/experiment_runs.md)에 따라 세션과 분리해 실행하고, 새 세션에서도 끝날 때까지 기다리거나 결과를 확인합니다. `config.toml.example`은 thread/depth 상한 예시이며 사용자 설정을 일괄 덮어쓰는 정책이 아닙니다.
