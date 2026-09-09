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

설치 진입점은 **`install.sh` 하나**입니다. macOS 기본 Bash 3.2와 Ubuntu에서 사용하며 `sh`로 실행하면 Bash로 전환합니다. Headroom 서비스에는 macOS 로그인 세션의 launchd 또는 Linux의 사용자 systemd가 필요합니다. WSL은 systemd를 활성화한 환경에 한하며 Native Windows와 Git Bash는 지원 범위가 아닙니다.

```bash
sh install.sh                       # 기본 설치 또는 갱신
sh install.sh --verify              # 설치 상태 확인만 수행
sh install.sh --cleanup-backups     # 키트 설치 백업만 명시적으로 정리
sh install.sh --help
```

기본 설치는 두 플랫폼의 전역 지침·agent·공통 스킬, 키트 gitignore 블록, Ponytail, Sequential Thinking MCP, Graphify, Headroom을 구성한 뒤 검증합니다. MCP·도구 설치는 유지하고, 사용 여부는 작업의 필요에 맞게 판단합니다.

- Graphify는 `graphifyy==0.9.39`, Headroom은 `headroom-ai[all]==0.34.0`을 사용합니다. uv 0.12.10과 Python 3.13을 키트 전용 경로에 자동 준비합니다. system Python이나 수동 `pip install`은 필요하지 않습니다. 버전뿐 아니라 관리 interpreter와 실제 proxy/MCP imports를 확인해 손상된 환경을 다시 설치합니다. `[all]`에는 proxy 의존성이 포함되며, 같은 버전이라는 이유만으로 외부 Headroom을 재사용하지 않습니다.
- Ponytail은 설치 시 확인한 원격 HEAD의 소스를 사용하고 실제 plugin 버전과 등록 상태를 확인합니다. 사용자 소유 marketplace는 보존하면서 Ponytail의 설치·활성 상태를 별도로 확인합니다. 누락된 plugin은 설치하고, Claude의 비활성 plugin은 활성화합니다. Codex의 비활성 plugin은 설정에서 활성화해야 한다는 오류로 중단합니다.
- Sequential Thinking은 키트 이름인 Codex `sequential_thinking`, Claude `sequential-thinking`으로 `@modelcontextprotocol/server-sequential-thinking@latest`를 등록합니다. 다른 이름의 사용자 MCP는 변경하지 않습니다.
- Codex의 `features.context_management.experimental_mode = true` 설정을 병합합니다. 이외의 모델·추론 설정은 유지합니다. 지원하지 않는 TOML 형태는 원본 교체 전에 오류로 중단합니다.
- Headroom은 호스트의 `127.0.0.1:8787`에서 상시 실행하며 Codex의 전역 provider와 두 CLI의 셸 분기를 구성합니다. 세션마다 설정 파일을 임시로 바꾸지 않습니다. 아래 사용 표를 참고하세요.
- Graphify의 전역 안내는 유용한 기존 그래프나 명시적인 Graphify 요청에 적용합니다. 단순 코드 질문을 위해 그래프 구축을 요구하지 않습니다.

Codex는 공식 standalone, Claude Code는 공식 native 설치로 통일합니다. 정상 native 설치는 재사용하고, 실행 파일·필수 명령·관리 launcher가 없거나 깨졌으면 공식 설치기로 복구합니다. 새 설치와 전체 kit 검증이 끝난 뒤 현재 npm prefix·홈의 NVM Node 버전별 prefix 및 현재 Homebrew에서 확인된 `@openai/codex`, `@anthropic-ai/claude-code`, `codex`, `claude-code`만 해당 패키지 관리자로 제거합니다. 수동 설치본이나 다른 사용자 디렉터리를 검색해서 지우지는 않습니다. Node.js가 20 미만이거나 Node.js·npx가 없거나 실행되지 않으면 공식 Node 24.13.0 아카이브의 SHA256을 확인해 설치합니다. Sequential Thinking은 설치 때 확인한 Node/npx의 절대 경로를 사용하는 작은 launcher로 등록하여 Desktop·daemon에서도 셸 초기화 없이 실행합니다.

처음에는 Git, Bash, curl 또는 wget, 인터넷 연결, 사용자 서비스 관리자가 필요합니다. 로그인·계정 이용 권한·조직 정책·pairing은 각 호스트에서 본인이 완료해야 합니다. 키트는 인증 정보를 복사하지 않습니다. `CLAUDE_CONFIG_DIR`과 기본 `~/.codex` 이외의 `CODEX_HOME`은 지원하지 않으며 설치 전에 거부합니다. Python minor 버전과 최상위 패키지는 고정하지만 운영체제별 wheel·전이 의존성까지 완전히 동일하다는 뜻은 아닙니다.

### Mac 로컬 작업과 여러 컴퓨터

각 컴퓨터에서 이 저장소를 받아 `sh install.sh`를 실행하고 새 터미널을 엽니다. 이후에는 평소처럼 `codex`와 `claude`를 사용합니다. Codex Desktop은 설치 후 재시작하여 새 provider를 읽게 합니다.

새 컴퓨터에서 Codex에 처음 로그인하거나 인증 방식을 바꾼 뒤에는 `sh install.sh`를 한 번 더 실행하고 Desktop/daemon을 재시작합니다. 재설치가 kit provider의 OAuth flag만 현재 인증 방식에 맞게 갱신합니다. 일반 세션 실행은 전역 설정을 바꾸지 않습니다.

| 실행 위치와 명령 | 처리 |
|---|---|
| Mac 또는 Ubuntu에서 `codex`, `codex exec`, `codex resume` | 해당 호스트의 persistent Headroom; CLI에서 프로젝트 헤더 추가 |
| Codex Desktop의 로컬 작업 | 해당 호스트의 전역 Headroom provider |
| SSH 접속 후 `codex` 또는 `claude` | SSH 서버의 설정·파일·Headroom |
| `codex remote-control …`, `codex app-server …` | 실제 managed Codex의 관리 명령; daemon의 모델 요청은 전역 Headroom provider 사용 |
| 일반 `claude` | 해당 호스트의 Headroom; 세션에만 URL·헤더·settings 전달 |
| `claude remote-control`, `claude --remote-control`, `claude --rc` | Headroom을 거치지 않는 Claude Remote Control |
| `codex_raw`, `claude_raw` | 셸 분기만 생략; 기존 전역 설정과 환경 변수는 그대로 적용 |

각 호스트의 여러 프로젝트·세션은 같은 proxy를 공유합니다. 일반 CLI의 프로젝트 표시는 현재 디렉터리명 또는 `HEADROOM_PROJECT`를 사용하며, Codex의 `--cd`도 반영합니다. Desktop/Remote Control의 여러 task를 dashboard에서 자동으로 프로젝트별 분리하는 기능은 보장하지 않습니다. 프로젝트별 provider·명시적인 CLI 설정으로 라우팅을 덮어쓰면 해당 설정이 우선할 수 있습니다.

**기본 설치는 Codex·Claude Remote Control을 켜지 않습니다.** Mac을 로컬 작업과 원격 서버 제어용으로만 쓰려면 기본 설치만 하면 됩니다. 이미 이 키트에서 원격 호스트로 선택한 컴퓨터는 재설치 때 그 선택을 유지합니다.

Git에는 지침·스킬·설치 로직만 공유합니다. `~/.codex`, `~/.claude`, `~/.headroom`, `~/.universal-research-agent-kit` 전체를 컴퓨터 사이에 동기화하지 마세요. 각 호스트가 자체 인증·PID·socket·서비스·pairing 상태를 가집니다. 특히 `codex_raw`도 전역 provider를 읽으므로 Headroom 우회를 뜻하지 않습니다.

### Codex Remote Control 호스트 켜기·확인·끄기

원격으로 작업을 실행할 **Ubuntu 또는 Mac 호스트에서** 아래 명령을 실행합니다. Mac에서 Ubuntu를 제어하려면 이 명령은 Ubuntu의 SSH 터미널에서 실행합니다.

```bash
sh install.sh                                # 최초 설치
codex login                                  # 그 호스트에서 로그인; 이미 로그인했다면 생략
sh install.sh --enable-codex-remote-control   # 원격 호스트로 명시적으로 선택
codex remote-control pair                    # 표시된 pairing을 Mac Codex App에서 완료
sh install.sh --remote-control-status
sh install.sh --headroom-status
```

`codex` 명령 하나로 일반 작업과 원격 관리 모두 실행합니다. 일반 명령과 원격 관리 모두 kit launcher가 공식 standalone을 선택합니다. npm 설치만으로는 관리 daemon bootstrap 요건을 충족하지 않습니다. Claude Code의 native 설치는 공식 권장 방식이며, Remote Control에 native만 허용된다는 의미는 아닙니다. [Claude 설치 안내](https://code.claude.com/docs/en/setup) 설치기의 `connected`와 `connecting`은 구분됩니다. `connecting`은 daemon이 시작됐지만 relay 연결을 기다리는 상태이며 pairing 성공을 뜻하지 않습니다. 상태 검사는 daemon 실행과 설정을 확인하며 실계정의 relay 연결·pairing까지 검증하지는 않습니다. [Codex daemon 원본](https://github.com/openai/codex/blob/main/codex-rs/app-server-daemon/README.md)

```bash
codex app-server daemon version             # daemon 상태
codex app-server daemon restart             # 설정 변경 후 명시적으로 재시작
codex remote-control start                  # relay 연결 재시도
sh install.sh --disable-codex-remote-control # 해당 호스트의 원격 제어 끄기
```

Ubuntu에서 SSH 종료 후나 재부팅 후에도 사용자 서비스가 실행되려면 linger가 필요할 수 있습니다. 설치기가 이를 확인해 안내합니다. 권한이 있는 호스트에서는 아래 설정을 한 번 적용하고, 거부되면 관리자에게 요청합니다.

```bash
loginctl enable-linger "$(id -un)"
loginctl show-user "$(id -un)" -p Linger
```

macOS의 사용자 LaunchAgent는 로그인 세션에 속합니다. 로그인 전·로그아웃 후·절전 중에도 원격 작업이 계속된다고 보장하지 않습니다. SSH 접속만 있고 GUI 사용자 서비스 domain이 없는 Mac은 기본 서비스 전제에 맞지 않습니다.

### Claude Remote Control

현재 Claude Code는 custom `ANTHROPIC_BASE_URL`과 Remote Control을 함께 지원하지 않습니다. 따라서 해당 명령은 subprocess에서 proxy URL을 제거하고 직접 Anthropic에 연결합니다. 전역·프로젝트 settings에 사용자 proxy URL이 남아 있으면 해당 파일을 알려주며, 사용자 설정을 임의로 지우지 않습니다. 일반 Headroom 세션 안에서 `/remote-control`로 전환하는 대신 처음부터 다음 명령으로 시작하세요. [Claude 공식 안내](https://code.claude.com/docs/en/remote-control)

```bash
cd /path/to/project
claude remote-control    # 또는 claude --rc, 짧은 helper인 claude_rc
```

로그인·프로젝트 trust·계정 및 조직의 Remote Control 허용 조건은 Claude에서 충족해야 합니다. SSH가 끊겨도 Claude 세션을 유지하려면 설치된 `tmux` 또는 `screen` 안에서 실행합니다. 예를 들어 `tmux new -s claude-rc`로 셸을 열고 위 명령을 실행한 뒤 `Ctrl-b d`로 detach합니다. 이 Claude 세션에는 Headroom이 적용되지 않습니다.

### Headroom 상태·문제 해결·제거

```bash
sh install.sh --verify
sh install.sh --headroom-status
curl -fsS http://127.0.0.1:8787/health
```

정상 판정에는 `Status: running`, `Healthy: yes`, `/readyz`, 그리고 health의 `deployment.profile`이 키트 소유 기록과 같은지 함께 확인합니다. 새 설치의 profile은 `research-agent-kit`이며, 기존 표준 설치를 인계한 호스트는 `default`를 유지합니다. 임의의 healthy listener를 키트 서비스로 간주하지 않습니다. 다른 서비스가 8787 포트를 사용하거나 사용자 설정이 표준 설치와 다르면 충돌 위치를 안내합니다.

예전 `headroom-default`도 `sh install.sh` 하나로 인계합니다. 로컬 8787 포트의 표준 Codex persistent-service인지 manifest·runner·OS 서비스 정의로 확인한 뒤 정상 종료하고, 배포·서비스 정의·Codex 설정·소유 기록을 백업합니다. 관리 Python과 의존성을 검사·복구한 뒤 표준 provider 블록을 검증하고 키트 소유로 등록합니다. 기존 서비스 이름과 manifest, provider 설정을 유지하면서 runner를 관리 Python으로 갱신하므로 별도 제거 스크립트나 Headroom의 `install remove` 명령이 필요하지 않습니다. 인증 방식이 바뀐 경우 기존 키트 설치와 동일하게 provider의 인증 플래그만 갱신하며, 이 인계 과정에서 인증 파일이나 세션 DB를 초기화하거나 세션 분류를 바꾸지 않습니다. 실패하면 파일 복구 후 원래 실행 중이던 서비스를 재개합니다. 사용자 지정 환경변수·proxy 옵션·provider 블록은 자동 인계하지 않습니다.

기존 Headroom MCP의 실행 경로·인수가 키트 설정과 같고 `HEADROOM_PROXY_URL`이 기본 주소 `http://127.0.0.1:8787`이거나 생략되어 있으면 설정을 그대로 재사용합니다. 주소의 명시 여부 때문에 재설치가 중단되지 않으며, 다른 주소·명령·추가 환경변수는 강제로 덮어쓰지 않습니다.

`No module named fastapi`와 같은 오류가 나면 작업을 마치고 `sh install.sh`를 다시 실행합니다. 설치기가 키트 소유 Headroom 서비스·MCP를 정상 종료한 뒤 관리 uv·Python·패키지 버전과 의존성을 검사합니다. 하나라도 실패하면 `~/.universal-research-agent-kit/tooling/`을 백업한 뒤 비우고 새 환경을 자동 설치합니다. 별도 복구 옵션이나 system Python의 수동 pip 작업은 필요하지 않습니다. 정상 환경은 재사용하며, 새 설치도 검증에 실패하면 안전하게 복구할 수 있는 경우 이전 상태로 되돌리고 오류를 알립니다. 중지된 키트 서비스가 예전 interpreter를 가리키는 경우에도 재설치 때 runner를 복구합니다.

서비스와 provider를 명시적으로 제거한 뒤 다시 구성하려면 다음 명령을 사용합니다.

```bash
sh install.sh --remove-headroom
sh install.sh
```

제거는 키트 소유 서비스·provider에만 적용합니다. 기존 root provider 설정과 블록 밖의 사용자 설정을 보존하고 Python 도구 환경·MCP는 남깁니다. 서비스 중지·제거에 실패하면 소유 기록과 환경, 백업을 보존하고 오류를 보고합니다. 권한·서비스 관리자 문제를 해결한 뒤 `--remove-headroom`으로 재시도합니다. 일반 세션을 모두 닫고 제거하세요. 제거 후 기본 설치 검증은 서비스가 없으므로 실패하며, 다음 설치가 서비스를 다시 만듭니다.

서비스 로그는 macOS의 `~/.headroom/deploy/research-agent-kit/`, Ubuntu의 해당 디렉터리와 `journalctl --user -u headroom-research-agent-kit.service`에서 확인합니다. 인계한 설치는 경로와 서비스 이름의 `research-agent-kit`을 `default`로 바꿉니다. API 키·pairing code·로그의 인증 정보를 저장소나 공유 보고서에 넣지 마세요.

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

기본 설치는 **키트 소유 Headroom 서비스와 MCP 서버를 정상 종료한 뒤 진행합니다.** 서비스는 등록 정보와 실제 실행 정의를 확인하고 macOS에서는 `launchctl bootout`, Ubuntu에서는 `systemctl --user stop`으로 중지합니다. MCP는 정확한 키트 실행 경로와 프로세스 시작 시각·명령을 다시 확인한 뒤 `SIGTERM`을 보냅니다. 종료를 확인하기 전에는 CLI 다운로드나 환경 교체를 시작하지 않습니다. `SIGKILL`로 강제 종료하지 않으며, 다른 Python·Graphify 작업이나 소유권을 확인할 수 없는 프로세스가 남아 있으면 설치를 중단합니다. `--verify`와 상태 조회는 종료 처리를 하지 않습니다.

갱신 전에는 진행 중인 작업을 마치세요. 설치 중에는 Headroom 연결이 잠시 끊기며, 완료 후 서비스는 다시 시작됩니다. stdio MCP 연결은 원래 클라이언트가 관리하므로 필요하면 Codex·Claude를 재시작해 다시 연결합니다. 클라이언트가 MCP를 즉시 재실행하거나 정상 종료를 거부하면 해당 클라이언트를 닫고 재시도합니다. 자동 중지가 불가능한 서비스는 Ubuntu의 `systemctl --user stop headroom-research-agent-kit.service`, macOS의 `launchctl bootout "gui/$(id -u)/com.headroom.research-agent-kit"`로 직접 중지할 수 있습니다. 다른 profile이나 과거 `headroom wrap` 세션은 해당 세션에서 종료하세요.

설치 잠금이 유지되는 동안 새 kit CLI 세션은 시작을 거절합니다. Python/패키지 교체 직전과 환경 rollback 전에도 실행 상태를 다시 확인합니다. 실패 시 설치 중 재시작된 키트 서비스를 다시 중지하고 환경·이전 runner를 복구한 뒤, 설치 전에 실행 중이었던 서비스를 재개합니다. 중지나 복구가 안전하지 않으면 환경·journal·재개 기록을 보존하고 실패를 알립니다. 프로세스 검사는 snapshot에 기반하며 외부에서 직접 시작하는 프로세스까지 원자적으로 막지는 못하므로 설치가 끝날 때까지 관련 클라이언트·서비스를 다시 시작하지 마세요. 종료 도우미는 패키지 의존성이 깨져도 실행할 수 있는 표준 라이브러리만 사용하며, 사용할 수 있는 Python 3.8 이상이 전혀 없으면 직접 중지를 안내합니다.

기존 ai-prompts를 설치한 호스트도 같은 `sh install.sh`로 갱신합니다. 이전 kit wrapper와 설치 상태가 확인되면 Codex의 정확한 legacy Headroom 표식만 제거하고, root provider의 `# was:` 또는 이전 백업의 해당 root 값만 복구합니다. 백업 이후 추가한 MCP·프로젝트·모델 설정은 현재 파일에서 유지합니다. 알려진 kit 경로를 가리키는 중복 Headroom MCP는 정리 후 다시 등록합니다. 재구성 때 kit의 옛 pip fallback venv도 tooling 백업에 보존하고 활성 경로에서는 제거합니다. 이 재구성은 키트 밖에 별도로 설치한 Python·Headroom·Graphify와 로그인 정보를 삭제하지 않습니다. 경로가 symlink여서 관리 범위를 확정할 수 없는 경우에는 자동 삭제를 거절합니다.

과거 Headroom 처리에서 MCP 시작 주석이 없어지고 종료 주석만 남은 경우에는 그 주석과 기존 설정을 그대로 보존하며 진행합니다. 주석 앞의 테이블을 키트 소유로 추정해 삭제하지 않습니다. 끝나지 않은 블록이나 provider 표식의 불균형, 잘못된 TOML은 계속 중단하고 문제의 표식을 알립니다.

소유 기록이 없는 custom provider·동명 MCP·다른 서비스의 8787 포트 사용은 자동 인수하지 않고 충돌 위치를 알립니다. kit 소유 서비스는 앞의 종료 확인 후 필요한 경우 옛 Python runner를 복구합니다. 일반 세션은 프로젝트의 옛 Claude proxy 설정을 세션 범위에서 덮어쓰며, Claude Remote Control은 파일에 남은 proxy 설정의 충돌을 안내합니다. 실행 중인 과거 wrapper가 파일을 쓸 수 있으므로 프로젝트 파일을 일괄 삭제하지 않습니다.

설치 후 새 터미널을 여세요. 이미 열린 셸의 함수·alias는 자식 설치 프로세스가 바꿀 수 없습니다. 직접 만든 `codex`/`claude` alias가 있다면 해당 alias를 해제하고 kit wrapper를 사용해야 합니다. 패키지 정리 권한이 부족하면 검증된 새 native 설치를 유지한 채 오류를 보고하며, 기존 패키지가 정리된 것처럼 성공 처리하지 않습니다. 로그인·인증·세션 디렉터리는 제거 대상이 아닙니다.

설치기는 `~/.universal-research-agent-kit/` 아래 백업·소유 목록·실행 journal을 사용합니다. 동시 설치를 막고, 백업에 성공한 뒤 변경을 기록하며, 실패하면 journal에 등록된 키트 관리 경로를 복구하되, 사용 중인 관리 환경은 덮어쓰지 않고 복구 자료를 보존합니다. 사용자 데이터 손실을 막는 경로 검사·백업·복구·소유 목록은 유지합니다. 외부 CLI가 만드는 캐시와 외부 등록 상태 전체까지 파일 journal로 복구한다고 주장하지 않습니다.

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
| `headroom/auto-wrap.sh`, `headroom/runtime.py` | `~/.config/headroom/` |

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
bash tests/test_cli_bootstrap.sh
python3 tests/test_install_busy_guard.py
python3 tests/test_headroom_maintenance.py
python3 tests/test_headroom_dispatch.py
python3 tests/test_headroom_runtime.py
python3 tests/test_headroom_legacy.py
```

- 문서·프롬프트 수정: 구조·참조와 내용의 정합성을 확인합니다.
- 코드 수정: 구문 검사와 영향을 받는 동작의 작은 검사를 실행합니다.
- 설치·복사·권한 수정: 임시 홈의 최초/반복 설치, 사용자 파일 보존, 실패 복구를 확인합니다.
- legacy 이행 검사는 두 개의 wrap 표식, 이전 root 값 복구, 새 설정 보존, 알려진 MCP 중복, 깨진 CLI 링크, npm/Homebrew 제거 순서와 반복 실행을 격리 fixture로 확인합니다. 실제 Mac/Ubuntu 전체 업그레이드를 수행한 증거는 아닙니다.
- 통합·도구 설치 변경: 가짜 외부 CLI로 등록·보존·정리·실패 경로를 확인합니다. 기본 전체 설치 검사는 skip 없이 최초·반복 설치와 필수 구성 누락을 확인합니다.
- 연구 주장: 해당 결론에 필요한 실제 근거를 확인합니다. 물리 안전·무결성 검사는 모든 물리 캡처에 적용합니다.

이미 통과한 무관한 검사는 반복하지 않습니다. 구조 검사는 모델 행동이나 실제 외부 서비스 설치 성공의 증거가 아닙니다. 행동을 평가할 때는 작은 수정, 중요한 결론 검토, 장기 실행, 읽기 전용 요청처럼 구분되는 실제 작업에서 범위·근거·완료 동작을 확인합니다.

CI는 macOS·Ubuntu의 구조 검사, detector/runner, 격리 설치와 mock 통합을 실행합니다. 원격 CI·실제 Linux/WSL 호스트·물리 장비·모델 행동은 실행 근거가 있을 때만 검증됐다고 보고합니다.

실제 Headroom이 설치된 환경에서 외부 모델 제공자에 요청하지 않는 별도 loopback 검사를 실행할 수 있습니다. 임시 홈과 임의 포트에서 만든 프로세스만 사용합니다.

```bash
~/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python -B tests/test_headroom_upstream.py
~/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python -B tests/test_headroom_upstream_lifecycle.py
```

위 검사의 `--codex`에는 shell function 이름이 아닌 실제 CLI 실행 파일을 지정합니다. 생략하면 Headroom의 HTTP/WebSocket 전송만 검사합니다. 합성 응답을 이용한 전송 검사이며 실제 계정 추론·압축 품질/절감률·Claude CLI·Codex의 실제 WebSocket 연결·OS 서비스 및 재부팅·pairing의 증거는 아닙니다.
