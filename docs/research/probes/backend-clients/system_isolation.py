#!/usr/bin/env python3
"""System-config sentinel probe in a private Linux user+mount namespace only.
No host /etc file is written. Requires existing unshare and mount; installs nothing.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def inside(root, original_mount_namespace):
    root = Path(root)
    # Refuse an accidental direct privileged invocation in the host namespace.
    if os.stat("/proc/self/ns/mnt").st_ino == int(original_mount_namespace) or os.getuid() != 0:
        raise RuntimeError("private mapped-root mount namespace required")
    subprocess.run(["mount", "--make-rprivate", "/"], check=True, timeout=5)
    subprocess.run(["mount", "--bind", str(root / "etc"), "/etc"], check=True, timeout=5)
    env = {"PATH": "/usr/bin:/bin", "HOME": str(root / "home"),
           "XDG_CONFIG_HOME": str(root / "xdg"), "SHELL": "/bin/sh", "LC_ALL": "C.UTF-8"}
    tmux = shutil.which("tmux")

    def command(socket, *args, controlled=False, startup=False):
        argv = [tmux, "-S", str(root / socket)]
        if not startup:
            argv += ["-N"]
        if controlled:
            argv += ["-f", str(root / "controlled.conf")]
        proc = subprocess.run(argv + list(args), env=env, capture_output=True, timeout=5)
        if len(proc.stdout) > 4096 or len(proc.stderr) > 4096:
            raise RuntimeError("bounded command-output limit exceeded")
        return proc.returncode, proc.stdout.decode().strip()

    sockets = ("positive.sock", "controlled.sock")
    try:
        rc, _ = command(sockets[0], "new-session", "-d", "-s", "positive", "/bin/sleep", "30", startup=True)
        assert rc == 0
        deadline = time.monotonic() + 3
        while not (root / "home/system-plugin").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        _, system_positive = command(sockets[0], "show-options", "-gqv", "@system_sentinel")
        _, user_positive = command(sockets[0], "show-options", "-gqv", "@user_sentinel")
        positive = system_positive == "loaded" and user_positive == "loaded" and all(
            (root / "home" / name).exists() for name in ("system-plugin", "user-plugin"))
        # Stop positive server before clearing marker; do not race a delayed plugin.
        command(sockets[0], "kill-server")
        for name in ("system-plugin", "user-plugin"):
            (root / "home" / name).unlink(missing_ok=True)
        rc, _ = command(sockets[1], "new-session", "-d", "-s", "controlled", "/bin/sleep", "30",
                        controlled=True, startup=True)
        assert rc == 0
        _, system_controlled = command(sockets[1], "show-options", "-gqv", "@system_sentinel", controlled=True)
        _, user_controlled = command(sockets[1], "show-options", "-gqv", "@user_sentinel", controlled=True)
        isolated = not system_controlled and not user_controlled and not any(
            (root / "home" / name).exists() for name in ("system-plugin", "user-plugin"))
        result = {"case": "system-user-plugin-config-isolation", "status": "pass" if positive and isolated else "fail",
                  "observed": {"private_mount_namespace": True, "system_sentinel_positive": system_positive == "loaded",
                               "user_sentinel_positive": user_positive == "loaded", "plugin_positive": positive,
                               "explicit_f_omitted_all_sentinels_and_plugins": isolated}}
        print(json.dumps(result))
        return 0 if result["status"] == "pass" else 1
    finally:
        for socket in sockets:
            command(socket, "kill-server")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--inside":
        return inside(sys.argv[2], sys.argv[3])
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="sess-bc-system-") as directory:
        root = Path(directory)
        for name in ("etc", "home/.config/tmux", "xdg/tmux"):
            (root / name).mkdir(parents=True, mode=0o700)
        # Synthetic NSS data only, never copy host account databases.
        (root / "etc/passwd").write_text("root:x:0:0:synthetic:/nonexistent:/bin/sh\n")
        (root / "etc/group").write_text("root:x:0:\n")
        (root / "etc/nsswitch.conf").write_text("passwd: files\ngroup: files\n")
        for category, files in (("system", [root / "etc/tmux.conf"]),
                                ("user", [root / "home/.tmux.conf", root / "home/.config/tmux/tmux.conf",
                                          root / "xdg/tmux/tmux.conf"])):
            for file in files:
                file.write_text(f'set -g @{category}_sentinel loaded\nrun-shell \'touch "$HOME/{category}-plugin"\'\n')
        (root / "controlled.conf").write_text("set -s exit-empty off\nset -s exit-unattached off\nset -g destroy-unattached off\n")
        namespace = str(os.stat("/proc/self/ns/mnt").st_ino)
        proc = subprocess.run(["unshare", "-Urnm", "--", sys.executable, str(Path(__file__).resolve()),
                               "--inside", directory, namespace], timeout=30)
        return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
