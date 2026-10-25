#!/usr/bin/python3
"""Synthetic child. Only allowlisted, harness-created values can reach evidence."""
import json
import os
from pathlib import Path
import sys

out = Path(os.environ["PROBE_OUT"])
data = {
    "argv": sys.argv[1:],
    "cwd": os.getcwd(),
    "tty": [os.isatty(i) for i in range(3)],
    "env": {k: os.environ[k] for k in (
        "PROBE_VALUE", "PROBE_KEEP", "PROBE_DROP", "TERM", "TMUX", "TMUX_PANE"
    ) if k in os.environ},
    "nvim_present": "NVIM" in os.environ,
}
if os.environ.get("PROBE_READ") == "1":
    out.with_suffix(".ready").write_text("ready")
    data["input"] = sys.stdin.readline(80).rstrip("\r\n")
tmp = out.with_suffix(".pending")
tmp.write_text(json.dumps(data))
tmp.replace(out)
