#!/bin/sh

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d)

trap 'rm -rf -- "$root"' EXIT HUP INT TERM

export HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_DATA_HOME="$root/data"
export XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache"
export SESS_TEST_REPO="$repo"

mkdir -p "$HOME"

failed=0

for test in "$repo"/tests/cases/*.lua; do
    export SESS_TEST_ROOT="$root/$(basename "$test" .lua)" SESS_TEST_CASE="$test"
    mkdir -p "$SESS_TEST_ROOT"
    if "${NVIM_BIN:-nvim}" --headless -u NONE -i NONE --noplugin -n \
        -c 'lua dofile(vim.env.SESS_TEST_REPO .. "/tests/runner.lua")'; then
        printf 'PASS %s\n' "$(basename "$test")"
    else
        failed=1
        printf 'FAIL %s\n' "$(basename "$test")"
    fi
done

exit "$failed"
