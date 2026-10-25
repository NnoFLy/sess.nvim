#!/bin/sh
# No installation, user config, inherited environment, or default tmux sockets.
set -eu
lane=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d /var/tmp/sess-durable-runtime-XXXXXX)
trap 'rm -rf -- "$root"' EXIT HUP INT TERM
chmod 700 "$root"
mkdir "$root/home"
findmnt -T "$root" -o TARGET,FSTYPE,OPTIONS
sha256sum /usr/bin/nvim /usr/bin/tmux /usr/bin/python3
env -i HOME="$root/home" PATH=/usr/bin:/bin LANG=C TERM=xterm-256color \
    SESS_DURABLE_ROOT="$root" /usr/bin/nvim --headless -u NONE -i NONE \
    --noplugin -n -l "$lane/fsync.lua"
env -i HOME="$root/home" PATH=/usr/bin:/bin LANG=C TERM=xterm-256color \
    /usr/bin/python3 -B "$lane/probe.py"
