# Research Agent Kit

Codex와 Claude Code에서 같은 연구 원칙과 스킬을 사용하는 개인 하네스입니다. **Simple is best**: 현재 요청에 필요 없는 구현 곁가지를 처음부터 만들지 않고, 필요한 근거와 검증은 온전히 남깁니다.

## 작업 원칙

- 작은 스크립트와 함수, 기존 코드와 표준 라이브러리부터 사용합니다. 현재 실험이나 실제 호출자가 필요로 할 때만 의존성·추상화·패키지·설정 계층을 추가합니다.
- 주석과 docstring은 현재 동작·의도·가정을 설명합니다. 코드 변경과 함께 최신화하고 수리 이력, 오래된 설명, 주석 처리한 미사용 코드는 남기지 않습니다. 이력은 Git에, 실제 미완료 작업은 작업 기록에 둡니다.
- 잘못된 수치, 가짜 성공, 조용한 대체 결과를 허용하지 않습니다. seed·설정·환경·코드 상태·원시 결과와 보고 수치의 연결, 합성/시뮬레이션/실측 구분을 유지합니다.
- 검증은 비판적이고 균형 있게 합니다. 확인된 성과와 유효 범위를 먼저 설명하고, 구현 실패·정보 부족·근거 있는 부정적 결과를 구분합니다. 선택적 추가 실험은 현재 범위의 성과를 무효로 만들지 않습니다.
- 부정적 결과는 구현·데이터·지표·기준선·불확실성·운영 조건·방법 가정에서 원인을 찾습니다. 결론을 바꿀 수 있는 검사를 우선하고, 원래 결과와 탐색적 후속 분석을 보존합니다. 좋은 결론을 얻기 위한 seed·지표·부분집합 선별은 금지합니다.
- 승인된 작업은 관련 실행·결과 확인·실패 수정까지 진행합니다. 읽기 전용 요청과 실제 승인 경계를 지키며, 이미 승인된 일상 단계마다 다시 묻지 않습니다.

항상 읽는 지침은 [Codex AGENTS.md](codex/AGENTS.md)와 [Claude CLAUDE.md](claude-code/CLAUDE.md)입니다. 상세 절차는 해당 작업에서 필요한 스킬·참고 문서만 읽습니다.

## 설치·갱신·확인

설치 진입점은 **`install.sh` 하나**입니다. macOS 기본 Bash 3.2, Linux, WSL에서 사용하며 `sh`로 실행하면 Bash로 전환합니다. Native Windows와 Git Bash는 지원 범위가 아닙니다.

```bash
sh install.sh                       # 기본 설치 또는 갱신
sh install.sh --verify              # 설치 상태 확인만 수행
sh install.sh --cleanup-backups     # 키트 설치 백업만 명시적으로 정리
sh install.sh --help
```

기본 설치는 두 플랫폼의 전역 지침·agent·공통 스킬, 키트 gitignore 블록, Ponytail, Sequential Thinking MCP, Graphify, Headroom을 구성한 뒤 검증합니다. MCP·도구 설치는 유지하고, 사용 여부는 작업의 필요에 맞게 판단합니다.

- Graphify는 `graphifyy==0.9.39`, Headroom은 `headroom-ai[all]==0.34.0`을 사용합니다. 필요한 버전이 없으면 키트 전용 환경에 설치합니다.
- Ponytail은 설치 시 확인한 원격 HEAD의 소스를 사용하고 실제 plugin 버전과 등록 상태를 확인합니다. 사용자 소유 marketplace는 보존하면서 Ponytail의 설치·활성 상태를 별도로 확인합니다. 누락된 plugin은 설치하고, Claude의 비활성 plugin은 활성화합니다. Codex의 비활성 plugin은 설정에서 활성화해야 한다는 오류로 중단합니다.
- Sequential Thinking은 키트 이름인 Codex `sequential_thinking`, Claude `sequential-thinking`으로 `@modelcontextprotocol/server-sequential-thinking@latest`를 등록합니다. 다른 이름의 사용자 MCP는 변경하지 않습니다.
- Codex의 `features.context_management.experimental_mode = true` 설정을 병합합니다. 이외의 모델·추론 설정은 유지합니다. 지원하지 않는 TOML 형태는 원본 교체 전에 오류로 중단합니다.
- Headroom은 `.zshrc`와 `.bashrc`의 키트 블록으로 연결합니다. 새 셸에서 `claude`와 `codex`는 `headroom wrap`을 사용하고, `claude_raw`와 `codex_raw`는 원래 CLI를 호출합니다.
- Graphify의 전역 안내는 유용한 기존 그래프나 명시적인 Graphify 요청에 적용합니다. 단순 코드 질문을 위해 그래프 구축을 요구하지 않습니다.

통합을 생략하지 않으면 Codex·Claude CLI와 Node.js·npx를 파일 변경 전에 확인합니다. 기본 통합에는 Git, 네트워크와 각 도구의 설치 조건도 필요합니다. Graphify 등록 경로의 제약 때문에 `CLAUDE_CONFIG_DIR`이 지정된 환경은 지원하지 않습니다. 기존 설정의 별도 위치를 추측해서 덮어쓰지 않습니다.

### 기존 환경 정리

```bash
sh install.sh --integrations none
```

`none`은 **통합 단계 생략이 아닙니다.** 키트 소유 Ponytail과 식별 가능한 LazyCodex 레거시 항목을 정리하고 Sequential Thinking·Graphify·Headroom은 유지합니다. 기본 `ponytail` 프로필도 레거시 항목을 정리합니다. 사용자 소유 스킬·agent·MCP와 무관한 설정은 보존하며, 사용자 `max_threads`를 일괄 변경하지 않습니다.

등록 경로와 소유권 기록으로 관리 대상을 구분합니다. 같은 키트 항목은 백업 후 갱신하고, 선택에서 제외된 키트 항목만 정리합니다. 통합 결과는 `~/.universal-research-agent-kit/integrations.state`, 도구 결과는 `tooling.state`에 기록하며 검증은 이 상태와 실제 설치를 함께 확인합니다.

오프라인 회귀 검사처럼 외부 변경을 생략해야 할 때는 다음 환경 변수를 사용합니다. 각각 해당 단계의 등록·제거를 생략하며 생략 상태를 기록합니다. 이 경우 완료·검증 메시지는 생략 범위를 표시하며 전체 기본 설치 완료로 보고하지 않습니다.

```bash
UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 \
UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1 sh install.sh
```

### 사용자 파일 보호

설치기는 `~/.universal-research-agent-kit/` 아래 백업·소유 목록·실행 journal을 사용합니다. 동시 설치를 막고, 백업에 성공한 뒤 변경을 기록하며, 실패하면 journal에 등록된 키트 관리 경로를 복구합니다. 사용자 데이터 손실을 막는 경로 검사·백업·복구·소유 목록은 유지합니다. 외부 CLI가 만드는 캐시와 외부 등록 상태 전체까지 파일 journal로 복구한다고 주장하지 않습니다.

`--cleanup-backups`는 설치 중에는 실행하지 않으며 키트 백업만 제거합니다. 소유 목록과 활성 설정은 보존합니다. `--verify`는 설치나 정리를 실행하지 않습니다.

## 원본과 설치 위치

공통 스킬은 **`skills/` 한 곳에서 관리**하고 두 플랫폼에 복사합니다. 설치 디렉터리는 각 플랫폼의 기존 위치를 유지합니다.

| 원본 | 설치 위치 |
|---|---|
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` |
| `codex/agents/*.toml` | `~/.codex/agents/` |
| `claude-code/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude-code/agents/*.md` | `~/.claude/agents/` |
| `skills/*` | `~/.agents/skills/`, `~/.claude/skills/` |
| Graphify CLI가 제공하는 스킬 | `~/.codex/skills/graphify/`, `~/.claude/skills/graphify/` |
| `headroom/auto-wrap.sh` | `~/.config/headroom/auto-wrap.sh` |

Codex agent 16개와 Claude agent 15개는 **플랫폼별 정의를 유지**합니다. 모델·effort·sandbox/도구 권한을 스킬에 합치지 않습니다. Codex는 역할별 TOML의 Astra 설정, Claude는 역할별 Opus/Sonnet 설정을 사용하며 실제 실행 시 호스트나 환경 override가 있는지 구분합니다. 주 에이전트의 모델을 이 키트가 대신 선택하지 않습니다.

위임은 독립 산출물, 큰 탐색의 요약, 중요한 결론의 전문 검토에 사용합니다. 최소 인원과 단계별 상호 호출을 강제하지 않습니다. 병렬 작성은 격리 worktree·소유권·병합 계획을 갖추고 자식은 재위임하지 않습니다. 큰 출력은 파일로, 부모에게는 요약과 근거 위치를 돌려줍니다.

## 스킬 사용 범위

| 스킬 | 필요한 시점 |
|---|---|
| `no-placeholder-development` | 연구 코드의 완전성·실패 처리·재현성을 구현하거나 확인할 때 |
| `code-comment-hygiene` | 주석 감사나 코드와 설명의 불일치를 조사할 때; 일상 변경은 주변 주석을 함께 갱신 |
| `research-domain-router` | 연구 분야가 교차하거나 필요한 근거가 불명확할 때 |
| `research-repo-design` | 실제 실험의 저장소 구조를 선택하거나 변경할 때 |
| `ai-ml-experiment` | ML 데이터 분할·평가·기준선·재현성을 설계하거나 판단할 때 |
| `hardware-vivado` | RTL·합성·구현·타이밍·자원 보고를 다룰 때 |
| `side-channel-analysis` | 부채널 실험·누설·방어 기법의 근거를 다룰 때 |
| `hardware-capture-integrity` | 실제 장비를 사용한 모든 캡처와 진단 |
| `evidence-gate` | 연구 결과나 중요한 구현·벤치마크·보고서 결론을 수용할 때 |
| `review-budget` | 독립 의미 검토의 필요성과 범위를 정할 때 |
| `adversarial-review` | 중요한 결론을 비판적으로 검토하거나 부정적 결과의 원인을 조사할 때 |
| `planned-work` | 여러 세션의 복구나 실질적인 인계 기록이 필요할 때 |
| `resource-aware-orchestration` | 독립 agent 작업, 로컬 동시 연산, 장기 실행을 조정할 때 |
| `sequential-thinking-mcp` | 어려운 계획·불명확한 디버깅·비싼 실험 설계·복잡한 결론 판단 |
| `report-writer` | 근거를 바탕으로 한국어 연구 보고서나 인계 문서를 작성할 때 |

스킬과 참고 문서는 내용의 정확성을 위한 지침입니다. 모든 스킬을 읽는 고정 순서나 빈 템플릿 작성 의무는 없습니다. 문서의 수치·인용·확실성·근거 한계를 문체 때문에 바꾸지 않습니다.

장기 실행의 명령·체크포인트·재개·중단과 플랫폼별 역할 선택은 [위임 스킬](skills/resource-aware-orchestration/SKILL.md)의 필요한 참고 문서에 있습니다. 물리 캡처는 [캡처 스킬](skills/hardware-capture-integrity/SKILL.md)과 해당 장비의 프로젝트 설정을 사용합니다. 특정 PicoScope/MCU 레이아웃과 첫-trigger 복구 절차는 적용 대상일 때 읽으며 다른 장비에 강제하지 않습니다.

## 검증

변경 경로의 검사부터 실행합니다. 문구의 정확한 일치나 특정 줄 수만으로 모델의 행동을 검증했다고 주장하지 않습니다.

```bash
bash scripts/validate_harness.sh
bash tests/test_codex_agent_runner.sh
bash tests/test_resource_detector.sh
bash tests/test_install_regression.sh
bash tests/test_integration_migration.sh
bash tests/test_tooling_install.sh
bash tests/test_default_install.sh
```

- 문서·프롬프트 수정: 구조·참조와 내용의 정합성을 확인합니다.
- 코드 수정: 구문 검사와 영향을 받는 동작의 작은 검사를 실행합니다.
- 설치·복사·권한 수정: 임시 홈의 최초/반복 설치, 사용자 파일 보존, 실패 복구를 확인합니다.
- 통합·도구 설치 변경: 가짜 외부 CLI로 등록·보존·정리·실패 경로를 확인합니다. 기본 전체 설치 검사는 skip 없이 최초·반복 설치와 필수 구성 누락을 확인합니다.
- 연구 주장: 해당 결론에 필요한 실제 근거를 확인합니다. 물리 안전·무결성 검사는 모든 물리 캡처에 적용합니다.

이미 통과한 무관한 검사는 반복하지 않습니다. 구조 검사는 모델 행동이나 실제 외부 서비스 설치 성공의 증거가 아닙니다. 행동을 평가할 때는 작은 수정, 중요한 결론 검토, 장기 실행, 읽기 전용 요청처럼 구분되는 실제 작업에서 범위·근거·완료 동작을 확인합니다.

CI는 macOS·Ubuntu의 구조 검사, detector/runner, 격리 설치와 mock 통합을 실행합니다. 원격 CI·실제 Linux/WSL 호스트·물리 장비·모델 행동은 실행 근거가 있을 때만 검증됐다고 보고합니다.
