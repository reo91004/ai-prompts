#!/bin/sh
# POSIX bootstrap so `sh install.sh` works on systems where /bin/sh is dash.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v bash >/dev/null 2>&1; then
    echo "Error: bash is required to run the kit installer." >&2
    exit 1
fi

exec bash "$ROOT/install_all.sh" "$@"
