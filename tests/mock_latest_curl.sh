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
case "$url" in
  https://pypi.org/pypi/graphifyy/json) version=0.9.82 ;;
  https://pypi.org/pypi/headroom-ai/json) version=0.40.0 ;;
  https://pypi.org/pypi/uv/json) version=0.12.24 ;;
  *) echo "Unexpected test network download: $url" >&2; exit 22 ;;
esac
printf '{"info":{"version":"%s"}}\n' "$version" > "$output"
