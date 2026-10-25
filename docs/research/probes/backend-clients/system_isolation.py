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


def process_identity(pid):
    with open(f"/proc/{pid}/stat") as file:
        text = file.read(4097)
    if len(text) > 4096:
        raise ValueError("process stat exceeds bound")
    return int(pid), text[text.rfind(")") + 2:].split()[19]


def absence_is_verified(queries, before, after, plugins_absent):
    # Failed queries and dead/replaced servers must never count as absence.
    return (all(rc == 0 and not value for rc, value in queries)
            and before is not None and before == after and plugins_absent)


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

    def server_identity(socket, controlled=False):
        rc, pid = command(socket, "display-message", "-p", "#{pid}", controlled=controlled)
        if rc:
            return None
        try:
            return process_identity(int(pid))
        except (OSError, ValueError, IndexError):
            return None

    sockets = ("positive.sock", "controlled.sock")
    try:
        rc, _ = command(sockets[0], "new-session", "-d", "-s", "positive", "/bin/sleep", "30", startup=True)
        assert rc == 0
        deadline = time.monotonic() + 3
        while not (root / "home/system-plugin").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        positive_before = server_identity(sockets[0])
        system_positive_rc, system_positive = command(sockets[0], "show-options", "-gqv", "@system_sentinel")
        user_positive_rc, user_positive = command(sockets[0], "show-options", "-gqv", "@user_sentinel")
        positive_live = positive_before is not None and positive_before == server_identity(sockets[0])
        positive = (system_positive_rc == user_positive_rc == 0 and positive_live
                    and system_positive == "loaded" and user_positive == "loaded" and all(
                        (root / "home" / name).exists() for name in ("system-plugin", "user-plugin")))
        # Stop positive server before clearing marker; do not race a delayed plugin.
        assert command(sockets[0], "kill-server")[0] == 0
        for name in ("system-plugin", "user-plugin"):
            (root / "home" / name).unlink(missing_ok=True)
        rc, _ = command(sockets[1], "new-session", "-d", "-s", "controlled", "/bin/sleep", "30",
                        controlled=True, startup=True)
        assert rc == 0
        before = server_identity(sockets[1], controlled=True)
        queries = [command(sockets[1], "show-options", "-gqv", option, controlled=True)
                   for option in ("@system_sentinel", "@user_sentinel")]
        after = server_identity(sockets[1], controlled=True)
        plugins_absent = not any((root / "home" / name).exists() for name in ("system-plugin", "user-plugin"))
        isolated = absence_is_verified(queries, before, after, plugins_absent)
        # Real missing-socket queries produce empty stdout too; that is NOT absence.
        missing_before = server_identity("missing.sock", controlled=True)
        missing_queries = [command("missing.sock", "show-options", "-gqv", option, controlled=True)
                           for option in ("@system_sentinel", "@user_sentinel")]
        missing_after = server_identity("missing.sock", controlled=True)
        controls = {
            "missing_server_rejected": all(rc != 0 for rc, _ in missing_queries)
                and not (root / "missing.sock").exists()
                and not absence_is_verified(missing_queries, missing_before, missing_after, True),
            "failed_system_query_rejected": not absence_is_verified([(1, ""), (0, "")], before, after, True),
            "failed_user_query_rejected": not absence_is_verified([(0, ""), (1, "")], before, after, True),
            "missing_identity_rejected": not absence_is_verified([(0, ""), (0, "")], None, None, True),
            "changed_identity_rejected": not absence_is_verified([(0, ""), (0, "")], (1, "a"), (1, "b"), True),
            "sentinel_present_rejected": not absence_is_verified([(0, "loaded"), (0, "")], before, after, True),
            "plugin_present_rejected": not absence_is_verified([(0, ""), (0, "")], before, after, False)}
        result = {"case": "system-user-plugin-config-isolation", "status": "pass" if positive and isolated else "fail",
                  "observed": {"private_mount_namespace": True, "system_sentinel_positive": system_positive == "loaded",
                               "user_sentinel_positive": user_positive == "loaded", "plugin_positive": positive,
                               "positive_queries_succeeded": system_positive_rc == user_positive_rc == 0,
                               "positive_same_live_server": positive_live,
                               "controlled_queries_succeeded": all(rc == 0 for rc, _ in queries),
                               "controlled_same_live_server": before is not None and before == after,
                               "explicit_f_omitted_all_sentinels_and_plugins": isolated}}
        control_result = {"case": "config-isolation-oracle-negative-controls",
                          "status": "pass" if all(controls.values()) else "fail", "observed": controls}
        print(json.dumps(result))
        print(json.dumps(control_result))
        return 0 if result["status"] == control_result["status"] == "pass" else 1
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
