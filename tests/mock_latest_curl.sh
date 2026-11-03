#!/bin/sh
# Test curl: answers the installer's latest-release lookups with the versions the
# mock tools report. Any other download is unexpected in these tests.
url="" output=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
[ -z "${KIT_TEST_CURL_LOG:-}" ] || printf '%s\n' "$url" >> "$KIT_TEST_CURL_LOG"
case "$url" in
  https://releases.openai.com/codex/channels/latest)
    [ "${KIT_TEST_CODEX_PRIMARY_FAIL:-0}" != 1 ] || exit 22
    printf '{"tag_name":"rust-v0.153.4","prerelease":false}\n' > "$output"; exit 0 ;;
  https://api.github.com/repos/openai/codex/releases/latest)
    printf '{"tag_name":"rust-v0.153.4","prerelease":false}\n' > "$output"; exit 0 ;;
  https://downloads.claude.ai/claude-code-releases/latest)
    printf '2.1.0\n' > "$output"; exit 0 ;;
  https://opencode.ai/update/api/latest/cli/npm)
    printf '{"version":"2.2.5","metadata":{"package":"@opencode/cli"},"active":true}\n' > "$output"; exit 0 ;;
  https://registry.npmjs.org/@modelcontextprotocol%2fserver-sequential-thinking/latest)
    printf '{"name":"@modelcontextprotocol/server-sequential-thinking","version":"2.0.0","engines":{"node":">=24"},"dist":{"integrity":"sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="}}\n' > "$output"; exit 0 ;;
  https://registry.npmjs.org/opencode-btw-plus/latest)
    cp "${KIT_TEST_BTW_METADATA:?}" "$output"; exit 0 ;;
  https://registry.npmjs.org/opencode-btw-plus/-/opencode-btw-plus-0.1.3.tgz)
    cp "${KIT_TEST_BTW_ARCHIVE:?}" "$output"; exit 0 ;;
  https://pypi.org/pypi/graphifyy/json) version=0.9.82 ;;
  https://pypi.org/pypi/headroom-ai/json) version=0.42.0 ;;
  https://pypi.org/pypi/uv/json) version=0.12.24 ;;
  *) echo "Unexpected test network download: $url" >&2; exit 22 ;;
esac
printf '{"info":{"version":"%s"}}\n' "$version" > "$output"
