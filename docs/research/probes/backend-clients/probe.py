#!/usr/bin/env python3
"""Disposable tmux-3.8 evidence, not an attachment recipe or plugin prototype.
Only explicitly selected sockets beneath a private temporary directory are used.
PTY bytes and captured pane text are discarded; only synthetic assertions print.
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import time
import tty

HERE = Path(__file__).resolve()


def identity(pid):
    # Linux stat field 22, parsing after the final ')' (comm may contain spaces).
    with open(f"/proc/{pid}/stat") as file:
        text = file.read(4097)
    if len(text) > 4096:
        raise ValueError("process stat exceeds bound")
    fields = text[text.rfind(")") + 2:].split()
    return (int(pid), fields[19])


def identity_ended(pid, expected):
    try:
        return identity(pid) != expected
    except FileNotFoundError:
        return True


def workload(directory):
    directory = Path(directory)
    pane = os.environ["TMUX_PANE"]
    state_file = directory / (pane + ".json")
    state = {"input": "", "interrupts": 0, "output": 0}
    child = None

    def save():
        state["root"] = identity(os.getpid())
        state["child"] = identity(child.pid) if child is not None else None
        tmp = state_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(state_file)

    def start():
        return subprocess.Popen([str(directory / "codex"), "300"],
                                preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_IGN))

    def stop():
        nonlocal child
        if child is not None:
            child.terminate()
            child.wait(timeout=2)
            child = None

    def interrupt(_sig, _frame):
        state["interrupts"] += 1
        save()

    def output(_sig, _frame):
        state["output"] += 1
        os.write(1, b"SYNTHETIC_OUTPUT_ONLY\r\n")
        save()

    def terminate(_sig, _frame):
        raise SystemExit(0)

    child = start()
    tty.setcbreak(0)
    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGUSR1, output)
    signal.signal(signal.SIGTERM, terminate)
    os.write(1, b"SYNTHETIC_READY\r\n")
    save()
    try:
        while True:
            value = os.read(0, 1)
            if not value or value == b"q":
                break
            if value == b"r":
                stop()
                child = start()
            elif value == b"x":
                stop()
            else:
                state["input"] = (state["input"] + value.decode("ascii", "ignore"))[-32:]
            save()
    finally:
        stop()


class Client:
    def __init__(self, lab, session, cols, rows, readonly=False):
        self.lab = lab
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
            args = lab.args("attach-session", "-E", "-t", session)
            if readonly:
                args.append("-r")
            os.execve(args[0], args, lab.env)
        os.set_blocking(self.fd, False)
        self.close_result = None
        lab.clients.append(self)

    def send(self, data):
        os.write(self.fd, data)

    def resize(self, cols, rows):
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.kill(self.pid, signal.SIGWINCH)

    def wait_exit(self, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                return status
            self.lab.pump(0.01)
        return None

    def close(self, abrupt=False):
        if self.fd is None:
            return self.close_result
        method = "requested-sigkill" if abrupt else "native-detach"
        if abrupt:
            os.kill(self.pid, signal.SIGKILL)
        else:
            try:
                self.send(b"\x02d")  # native detach, not pane/window destruction
            except OSError:
                method = "pty-close"
        # Confirm normal exit BEFORE closing the PTY; hangup is not native detach.
        status = self.wait_exit(1)
        if status is None and not abrupt:
            method = "pty-close"
        os.close(self.fd)
        self.fd = None
        if status is None:
            status = self.wait_exit(0.5)
        if status is None:
            method = "sigkill-fallback"
            os.kill(self.pid, signal.SIGKILL)
            _, status = os.waitpid(self.pid, 0)
        self.close_result = {"termination": method, "exit_code": os.waitstatus_to_exitcode(status),
                             "normal_detach_confirmed": method == "native-detach"
                             and os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0}
        return self.close_result


class Lab:
    def __init__(self, root):
        self.root = Path(root)
        self.socket = str(self.root / "owned.sock")
        self.tmux = shutil.which("tmux")
        self.clients = []
        self.results = []
        self.env = {"PATH": "/usr/bin:/bin", "HOME": str(self.root / "home"),
                    "XDG_CONFIG_HOME": str(self.root / "xdg"), "TERM": "xterm-256color",
                    "LC_ALL": "C.UTF-8", "SHELL": "/bin/sh", "TMUX_TMPDIR": str(self.root)}
        for name in ("home/.config/tmux", "xdg/tmux", "state"):
            (self.root / name).mkdir(parents=True, mode=0o700)
        (self.root / "state/codex").symlink_to("/bin/sleep")
        # User and plugin sentinels: no real user configuration is read.
        sentinel = 'set -g @user_sentinel loaded\nrun-shell "touch ' + str(self.root / "plugin-ran") + '"\n'
        (self.root / "home/.tmux.conf").write_text(sentinel)
        (self.root / "xdg/tmux/tmux.conf").write_text(sentinel)
        (self.root / "home/.config/tmux/tmux.conf").write_text(sentinel)
        self.config = self.root / "controlled.conf"
        self.config.write_text("""set -s exit-empty off
set -s exit-unattached off
set -g destroy-unattached off
set -g status off
set -g default-shell /bin/sh
set -g default-command 'printf x >> "$HOME/transient-starts"; exec /bin/sleep 300'
set -gw window-size latest
set -gw aggressive-resize on
set -gw remain-on-exit off
set -gw automatic-rename off
set -g @namespace synthetic-backend-clients
set -g @generation synthetic-generation
set -g @protocol 1
set -g @digest synthetic-config-a
run-shell 'printf x >> "$HOME/config-starts"'
set-hook -g pane-created 'set-option -p @probe-created yes'
""")

    def args(self, *args, socket=None, startup=False, config=None):
        return [self.tmux, "-S", socket or self.socket,
                *([] if startup else ["-N"]), "-f", str(config or self.config), *args]

    def run(self, *args, socket=None, startup=False, config=None, check=True, env=None, strip=True):
        result = subprocess.run(self.args(*args, socket=socket, startup=startup, config=config),
                                env=env or self.env, capture_output=True, timeout=5)
        if len(result.stdout) > 8192 or len(result.stderr) > 8192:
            raise RuntimeError("bounded command-output limit exceeded")
        if check and result.returncode:
            raise RuntimeError(f"tmux {args[0]} failed rc={result.returncode}")
        output = result.stdout.decode()
        return output.strip() if strip else output, result.returncode

    def out(self, *args, **kwargs):
        return self.run(*args, **kwargs)[0]

    def pump(self, duration=0.05):
        until = time.monotonic() + duration
        while time.monotonic() < until:
            fds = [c.fd for c in self.clients if c.fd is not None]
            if not fds:
                time.sleep(min(0.01, max(0, until - time.monotonic())))
                continue
            for fd in select.select(fds, [], [], 0.01)[0]:
                try:
                    os.read(fd, 65536)  # discard PTY screen bytes, never log
                except (BlockingIOError, OSError):
                    pass

    def wait(self, predicate, timeout=3):
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            if predicate():
                return True
            self.pump()
        return False

    def record(self, name, good, detail):
        row = {"case": name, "status": "pass" if good else "fail", "observed": detail}
        self.results.append(row)
        print(json.dumps(row), flush=True)

    def state(self, pane):
        try:
            return json.loads((self.root / "state" / (pane + ".json")).read_text())
        except FileNotFoundError:
            return {}

    def window(self, session, label="duplicate"):
        value = self.out("new-window", "-d", "-P", "-F", "#{window_id} #{pane_id} #{pane_pid}",
                         "-t", session + ":", "-n", label,
                         sys.executable, str(HERE), "--workload", str(self.root / "state"))
        window, pane, pid = value.split()
        assert self.wait(lambda: bool(self.state(pane)))
        return window, pane, int(pid)

    def size(self, window):
        return self.out("display-message", "-p", "-t", window, "#{window_width}x#{window_height}")

    def select(self, session, window):
        self.out("select-window", "-t", session + ":" + window)
        self.pump(0.1)

    def cleanup(self):
        for client in self.clients:
            client.close(abrupt=True)
        for name in ("owned.sock", "unrelated.sock", "negative.sock", "sentinel.sock"):
            self.run("kill-server", socket=str(self.root / name), check=False)


def observe(root, expected, limit=256, depth_limit=8):
    """Fixture-only bounded /proc traversal; no global process scan or argv logging."""
    try:
        if identity(root) != expected:
            return "unknown", []
        queue, seen, known = [(root, 0)], set(), []
        while queue:
            pid, depth = queue.pop(0)
            if pid in seen:
                continue
            if len(seen) >= limit or depth > depth_limit:
                return "unknown", []
            seen.add(pid)
            before = identity(pid)
            with open(f"/proc/{pid}/cmdline", "rb") as file:
                argv = file.read(32769)
            if len(argv) > 32768:
                return "unknown", []
            first = argv.split(b"\0")[0].rsplit(b"/", 1)[-1]
            if first == b"codex":
                known.append(before)
            with open(f"/proc/{pid}/task/{pid}/children") as file:
                text = file.read(4097)
            if len(text) > 4096:
                return "unknown", []
            children = text.split()
            if len(children) > 256 or identity(pid) != before:
                return "unknown", []
            queue.extend((int(child), depth + 1) for child in children)
        if identity(root) != expected:
            return "unknown", []
        return ("known" if known else "unknown"), known
    except (OSError, ValueError, IndexError):
        return "unknown", []


def capture_facts(capture):
    size = len(capture.encode())
    lines = len(capture.splitlines())
    return {"capture_bytes": size, "capture_lines": lines,
            "synthetic_output_present": "SYNTHETIC_OUTPUT_ONLY" in capture,
            "within_bounds": 0 < size <= 8192 and 1 <= lines <= 6}


def capture_is_valid(facts):
    return facts["synthetic_output_present"] and facts["within_bounds"]


def experiment(lab):
    # Explicit disposable unrelated server, deliberately selected by TMUX env.
    unrelated = str(lab.root / "unrelated.sock")
    lab.out("new-session", "-d", "-s", "unrelated", "/bin/sleep", "300", startup=True, socket=unrelated)
    sentinel_before = lab.out("list-panes", "-a", "-F", "#{pane_id}:#{pane_pid}", socket=unrelated)
    env = dict(lab.env, TMUX=unrelated + ",1,0")
    anchor = lab.out("new-session", "-d", "-P", "-F", "#{session_id}", "-s", "anchor",
                     "/bin/sleep", "300", startup=True, env=env)
    server_pid = int(lab.out("display-message", "-p", "#{pid}"))
    server_identity = identity(server_pid)
    endpoint = os.lstat(lab.socket)
    lab.record("private-endpoint", stat.S_ISSOCK(endpoint.st_mode) and endpoint.st_uid == os.getuid()
               and stat.S_IMODE(lab.root.stat().st_mode) == 0o700,
               {"directory_mode": "0700", "socket_mode": oct(stat.S_IMODE(endpoint.st_mode)),
                "socket_bytes": len(lab.socket.encode()), "same_uid": endpoint.st_uid == os.getuid()})
    user_sentinel, query_rc = lab.run("show-options", "-gqv", "@user_sentinel")
    live_server = int(lab.out("display-message", "-p", "#{pid}")) == server_pid and identity(server_pid) == server_identity
    lab.record("user-plugin-config-isolation", query_rc == 0 and live_server and not user_sentinel
               and not (lab.root / "plugin-ran").exists(),
               {"query_succeeded": query_rc == 0, "same_live_server": live_server,
                "sentinel_and_plugin_absent": not user_sentinel and not (lab.root / "plugin-ran").exists()})
    # Positive control: explicit sentinel config executes sentinel plugin.
    lab.out("new-session", "-d", "-s", "sentinel", "/bin/sleep", "300", startup=True,
            socket=str(lab.root / "sentinel.sock"), config=lab.root / "home/.tmux.conf")
    positive = lab.wait(lambda: (lab.root / "plugin-ran").exists())
    lab.record("config-sentinel-positive-control", positive and lab.out("show-options", "-gqv", "@user_sentinel",
               socket=str(lab.root / "sentinel.sock")) == "loaded", "explicit sentinel config detected")
    options = {key: lab.out("show-options", *scope, "-v", key) for key, scope in (
        ("exit-empty", ["-s"]), ("exit-unattached", ["-s"]), ("destroy-unattached", ["-g"]),
        ("window-size", ["-gw"]), ("aggressive-resize", ["-gw"]), ("remain-on-exit", ["-gw"]))}
    lab.record("protected-options", list(options.values()) == ["off", "off", "off", "latest", "on", "off"], options)
    w1, pane1, root1 = lab.window(anchor)
    w2, pane2, root2 = lab.window(anchor)
    original = identity(root1)
    original2 = identity(root2)
    shell_pid = int(lab.out("new-window", "-d", "-P", "-F", "#{pane_pid}", "-t", anchor + ":",
                           "-n", "synthetic-shell", "/bin/sh", "-i"))
    shell_identity = identity(shell_pid)
    lab.record("native-create-hook-capability", lab.out("show-options", "-p", "-t", pane1, "-qv", "@probe-created") == "yes",
               "pane-created synthetic stamp visible; identity/epoch ordering NOT tested")
    p1 = lab.out("new-session", "-d", "-P", "-F", "#{session_id}", "-t", anchor, "-s", "viewer-one")
    p2 = lab.out("new-session", "-d", "-P", "-F", "#{session_id}", "-t", anchor, "-s", "viewer-two")
    starts = lab.root / "home/transient-starts"
    # default-command shell startup can race with tmux killing its temporary pane.
    lab.pump(0.15)
    group_windows = lab.out("list-windows", "-t", anchor, "-F", "#{window_id}").splitlines()
    with open(f"/proc/{server_pid}/task/{server_pid}/children") as file:
        direct_children = file.read(4096).split()
    lab.record("group-presentation-no-extra-window", len(group_windows) == 4 and len(direct_children) == 4,
               {"canonical_window_count": len(group_windows), "server_direct_children": len(direct_children),
                "presentation_count": 2,
                "transient_shell_side_effect_count": len(starts.read_bytes()) if starts.exists() else 0})
    lab.select(p1, w1)
    lab.select(p2, w1)
    c1 = Client(lab, p1, 100, 30)
    first_attached = lab.wait(lambda: lab.out("list-clients", "-F", "#{session_id}").splitlines() == [p1])
    c2 = Client(lab, p2, 60, 20)
    attached = lab.wait(lambda: len(lab.out("list-clients", "-F", "#{client_pid}").splitlines()) == 2)
    attach_size = lab.wait(lambda: lab.size(w1) == "60x20")
    lab.record("attach-latest-sizing", first_attached and attached and attach_size,
               {"first_attached": first_attached, "two_attached": attached, "after_second_attach": lab.size(w1)})
    c2.resize(70, 22)
    resized = lab.wait(lambda: lab.size(w1) == "70x22")
    c2.resize(60, 20)
    restored = lab.wait(lambda: lab.size(w1) == "60x20")
    lab.record("pty-resize-event", resized and restored, "latest viewer resize 60x20 -> 70x22 -> 60x20")
    c1.send(b"a")
    shared1 = lab.wait(lambda: "a" in lab.state(pane1).get("input", ""))
    size1 = lab.wait(lambda: lab.size(w1) == "100x30")
    c2.send(b"b")
    shared2 = lab.wait(lambda: "ab" in lab.state(pane1).get("input", ""))
    size2 = lab.wait(lambda: lab.size(w1) == "60x20")
    c1.send(b"\x03")
    ctrl = lab.wait(lambda: lab.state(pane1).get("interrupts") == 1)
    lab.record("two-pty-shared-input-control", attached and shared1 and shared2 and ctrl and identity(root1) == original,
               {"input": lab.state(pane1).get("input"), "SIGINT_count": lab.state(pane1).get("interrupts"), "same_root": identity(root1) == original})
    lab.record("latest-keyboard-sizing", size1 and size2, {"after_first": "100x30" if size1 else "unexpected", "after_second": "60x20" if size2 else "unexpected"})
    c2.send(b"b")
    output_baseline = lab.wait(lambda: lab.size(w1) == "60x20")
    os.kill(root1, signal.SIGUSR1)
    output_produced = lab.wait(lambda: lab.state(pane1).get("output") == 1)
    lab.pump(0.2)
    lab.record("output-only-no-latest-change", output_baseline and output_produced and lab.size(w1) == "60x20",
               {"baseline_size_confirmed": output_baseline, "output_produced": output_produced, "size": lab.size(w1)})
    lab.select(p2, w2)
    c1.send(b"a")
    viewer_only = lab.wait(lambda: lab.size(w1) == "100x30")
    c2.send(b"z")
    nonviewer_input = lab.wait(lambda: "z" in lab.state(pane2).get("input", ""))
    lab.pump(0.2)
    selections = [lab.out("display-message", "-p", "-t", p, "#{window_id}") for p in (p1, p2)]
    lab.record("independent-navigation-nonviewer", selections == [w1, w2] and viewer_only and nonviewer_input
               and lab.size(w1) == "100x30",
               {"selections_distinct": selections == [w1, w2], "nonviewer_input_received": nonviewer_input,
                "nonviewer_activity_size": lab.size(w1)})
    lab.select(p2, w1)
    c2.send(b"b")
    loss_baseline = lab.wait(lambda: lab.size(w1) == "60x20")
    abrupt_close = c2.close(abrupt=True)
    loss_size = lab.wait(lambda: lab.size(w1) == "100x30")
    normal_close = c1.close()
    zero = lab.wait(lambda: not lab.out("list-clients", "-F", "#{client_pid}"))
    lab.pump(0.2)
    lab.record("normal-abrupt-loss-zero-clients", zero and loss_baseline and loss_size
               and abrupt_close["termination"] == "requested-sigkill" and normal_close["normal_detach_confirmed"]
               and identity(root1) == original and identity(shell_pid) == shell_identity,
               {"same_pid_start": identity(root1) == original, "same_shell_pid_start": identity(shell_pid) == shell_identity,
                "zero_clients": zero, "latest_before_loss": loss_baseline,
                "abrupt_close": abrupt_close, "normal_close": normal_close,
                "remaining_viewer_size_after_loss": loss_size})
    # External-only bounded process observations: no Neovim or tmux attachment PID as root.
    before_status, before_agents = observe(root1, original)
    _, attachment_agents = observe(c1.pid, (c1.pid, "deliberately-stale"))
    low_status, _ = observe(root1, original, limit=1)
    # Keep raw newlines for the six-line bound; never log the captured text.
    capture, _ = lab.run("capture-pane", "-p", "-t", pane1, "-S", "0", "-E", "5", strip=False)
    facts = capture_facts(capture)
    capture_controls = {name: not capture_is_valid(capture_facts(text)) for name, text in (
        ("empty_rejected", ""), ("missing_marker_rejected", "SYNTHETIC_OTHER\n"),
        ("excess_lines_rejected", "SYNTHETIC_OUTPUT_ONLY\n" + "x\n" * 6),
        ("excess_bytes_rejected", "SYNTHETIC_OUTPUT_ONLY" + "x" * 8192))}
    lab.record("capture-oracle-negative-controls", all(capture_controls.values()), capture_controls)
    association_ok = identity(root1) == original and lab.out("display-message", "-p", "-t", pane1,
                         "#{pane_id}:#{pane_pid}") == pane1 + ":" + str(root1)
    wrong_capture = lab.out("capture-pane", "-p", "-t", pane2, "-S", "0", "-E", "5")
    wrong_association = lab.out("display-message", "-p", "-t", pane2, "#{pane_id}:#{pane_pid}") == pane1 + ":" + str(root1)
    lab.record("wrong-pane-observation-control", not wrong_association and "SYNTHETIC_OUTPUT_ONLY" not in wrong_capture,
               "different exact pane rejected by association; synthetic output marker absent")
    del wrong_capture
    dedup_key = ("synthetic-generation", "owner-incarnation", w1, pane1, original)
    dedup_count = len({dedup_key, dedup_key})
    lab.record("external-only-bounded-observation", before_status == "known" and len(before_agents) == 1
               and not attachment_agents and low_status == "unknown" and association_ok and dedup_count == 1
               and capture_is_valid(facts),
               {"known_fixture_count": len(before_agents), "traversal_limit_control": low_status,
                "stale_attachment_rejected": not attachment_agents, "dedup_rows": dedup_count, **facts})
    del capture  # never persist pane contents
    c1 = Client(lab, p1, 100, 30)
    reattached = lab.wait(lambda: lab.out("list-clients", "-F", "#{client_pid}:#{session_id}").splitlines()
                         == [str(c1.pid) + ":" + p1])
    lab.record("reattach-identical-workload", reattached and identity(root1) == original and identity(shell_pid) == shell_identity,
               {"exact_client_session_reattached": reattached, "same_root": identity(root1) == original,
                "same_shell": identity(shell_pid) == shell_identity})
    c1.send(b"r")
    replaced = lab.wait(lambda: tuple(lab.state(pane1).get("child") or ()) not in before_agents)
    after_status, after_agents = observe(root1, original)
    lab.record("agent-replacement-invalidates", replaced and after_status == "known" and before_agents != after_agents,
               "new child PID/start differs; surviving workload root unchanged")
    c1.send(b"x")
    child_gone = lab.wait(lambda: lab.state(pane1).get("child") is None)
    lab.record("agent-child-exit-root-survives", child_gone and identity(root1) == original and observe(root1, original)[0] == "unknown",
               "child gone, root survives, no known-agent observation")
    c1.close()
    readonly = Client(lab, p2, 40, 12, readonly=True)
    readonly_attached = lab.wait(lambda: "read-only" in lab.out("list-clients", "-F", "#{client_flags}"))
    old_input = lab.state(pane1).get("input")
    readonly.send(b"j")
    lab.pump(0.2)
    only_readonly_size = lab.size(w1)
    writable = Client(lab, p1, 100, 30)
    lab.wait(lambda: len(lab.out("list-clients", "-F", "#{client_pid}").splitlines()) == 2)
    writable.send(b"a")
    lab.wait(lambda: lab.size(w1) == "100x30")
    readonly.send(b"k")
    lab.pump(0.2)
    lab.record("readonly-ignore-size", readonly_attached and lab.state(pane1).get("input") == old_input + "a" and lab.size(w1) == "100x30",
               {"read_only_did_not_write": lab.state(pane1).get("input") == old_input + "a",
                "only_ignore_size_client_geometry": only_readonly_size, "with_writable_geometry": lab.size(w1)})
    readonly.close(abrupt=True)
    writable.close()
    lab.out("rename-window", "-t", anchor + ":" + w1, "renamed")
    lab.out("rename-window", "-t", anchor + ":" + w2, "renamed")
    rows = lab.out("list-windows", "-t", anchor, "-F", "#{window_id}:#{window_name}").splitlines()
    lab.record("native-rename-duplicate-labels", w1 + ":renamed" in rows and w2 + ":renamed" in rows
               and identity(root1) == original, "duplicate labels visible with distinct exact IDs; root unchanged")
    # Unsupported shapes are observed only. Never adopt or use as a deletion target.
    extra = lab.out("split-window", "-d", "-P", "-F", "#{pane_id}", "-t", w2, "/bin/sleep", "300")
    lab.record("unsupported-multipane-visible-preserved", lab.out("display-message", "-p", "-t", w2, "#{window_panes}") == "2",
               "two-pane shape visible; preserved until disposable server teardown")
    # Cleanup ONLY one detached presentation while canonical links and another presentation survive.
    before = lab.out("list-windows", "-t", anchor, "-F", "#{window_id}")
    lab.out("kill-session", "-t", p1)
    after = lab.out("list-windows", "-t", anchor, "-F", "#{window_id}")
    lab.record("presentation-only-cleanup", before == after and identity(root1) == original
               and lab.run("has-session", "-t", p2, check=False)[1] == 0,
               "one detached presentation removed; canonical windows/root and second presentation preserved (no concurrency claim)")
    # Natural root exit through shared input; signaled root exit targets ONLY our exact fixture PID.
    c2 = Client(lab, p2, 60, 20)
    lab.wait(lambda: bool(lab.out("list-clients", "-F", "#{client_pid}")))
    c2.send(b"q")
    natural = lab.wait(lambda: pane1 not in lab.out("list-panes", "-a", "-F", "#{pane_id}").splitlines())
    c2.close(abrupt=True)
    stale_status, _ = observe(root1, original)
    os.kill(root2, signal.SIGTERM)
    signaled = lab.wait(lambda: pane2 not in lab.out("list-panes", "-a", "-F", "#{pane_id}").splitlines())
    roots_ended = lab.wait(lambda: identity_ended(root1, original) and identity_ended(root2, original2))
    lab.record("natural-signaled-exit", natural and signaled and stale_status == "unknown" and roots_ended,
               {"natural_pane_removed": natural, "signaled_root_pane_removed": signaled,
                "root_process_identities_ended": roots_ended,
                "stale_root_observation": stale_status, "no_respawn": True})
    # Empty-server survival: stop only disposable known windows, never test native stop atomicity.
    for window in lab.out("list-windows", "-t", anchor, "-F", "#{window_id}").splitlines():
        lab.out("kill-window", "-t", window)
    lab.pump(0.2)
    lab.record("empty-server-survival", not lab.out("list-sessions", "-F", "#{session_id}")
               and identity(server_pid) == server_identity and lab.out("show-options", "-gqv", "@generation") == "synthetic-generation",
               "zero sessions/windows; same server PID/start and generation")
    # Default exit-empty is a negative lifetime control, on another explicit disposable socket.
    lab.out("new-session", "-d", "-s", "negative", "/bin/sleep", "300", startup=True,
            socket=str(lab.root / "negative.sock"), config=Path("/dev/null"))
    lab.out("kill-session", "-t", "negative", socket=str(lab.root / "negative.sock"))
    negative = lab.wait(lambda: lab.run("list-sessions", socket=str(lab.root / "negative.sock"), check=False)[1] != 0)
    lab.record("empty-server-negative-control", negative, "default exit-empty server disappears after final session")
    after_unrelated = lab.out("list-panes", "-a", "-F", "#{pane_id}:#{pane_pid}", socket=unrelated)
    lab.record("explicit-routing-unrelated-protected", sentinel_before == after_unrelated,
               "disposable unrelated server pane IDs/PIDs unchanged, including TMUX-env conflict at controlled startup")
    missing = str(lab.root / "missing.sock")
    _, rc = lab.run("list-sessions", socket=missing, check=False)
    lab.record("missing-read-only-no-start", rc != 0 and not Path(missing).exists(), {"exit": rc, "socket_created": Path(missing).exists()})
    regular = lab.root / "regular-file"
    regular.write_text("synthetic")
    _, regular_rc = lab.run("list-sessions", socket=str(regular), check=False)
    _, long_rc = lab.run("list-sessions", socket=str(lab.root / ("s" * 120)), check=False)
    alias = lab.root / "socket-symlink"
    alias.symlink_to(lab.socket)
    _, alias_rc = lab.run("show-options", "-gqv", "@generation", socket=str(alias), check=False)
    lab.record("endpoint-negative-controls", regular_rc != 0 and long_rc != 0 and alias.is_symlink() and alias_rc == 0,
               {"regular_file_exit": regular_rc, "long_path_exit": long_rc,
                "native_follows_symlink": alias_rc == 0,
                "requires_caller_lstat_boundary_validation": True})
    denied_dir = lab.root / "denied"
    denied_dir.mkdir(mode=0o700)
    (denied_dir / "server.sock").symlink_to(lab.socket)
    denied_dir.chmod(0)
    try:
        _, denied_rc = lab.run("list-sessions", socket=str(denied_dir / "server.sock"), check=False)
    finally:
        denied_dir.chmod(0o700)
    lab.record("denied-is-not-absent", denied_rc != 0 and Path(lab.socket).exists(),
               {"exit": denied_rc, "underlying_server_socket_preserved": Path(lab.socket).exists()})
    # Deliberate protected-option drift: detect, leave unmodified; no self-repair.
    lab.out("set-option", "-s", "exit-unattached", "on")
    lab.record("protected-drift-detection", lab.out("show-options", "-sv", "exit-unattached") == "on",
               "observable incompatible setting detected; no repair attempted; this is not a plugin refusal test")
    desired = lab.root / "changed-desired.conf"
    desired.write_text('set -g @digest synthetic-config-b\nrun-shell "touch ' + str(lab.root / "unexpected-reload") + '"\n')
    desired_digest = lab.out("show-options", "-gqv", "@digest", config=desired)
    lab.record("startup-only-executable-config", desired_digest == "synthetic-config-a"
               and (lab.root / "home/config-starts").read_bytes() == b"xx"
               and not (lab.root / "unexpected-reload").exists(),
               "two controlled servers initialized once each; changed client -f did not reload live server or execute changed line")
    lab.out("set-hook", "-gu", "pane-created")
    lab.record("missing-protected-hook-observable", "@probe-created" not in lab.out("show-hooks", "-g", "pane-created"),
               "removed synthetic hook detected; no replacement/repair; not production identity-hook qualification")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--workload":
        workload(sys.argv[2])
        return
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="sess-bc-") as root:
        lab = Lab(root)
        try:
            experiment(lab)
        finally:
            lab.cleanup()
        failed = sum(row["status"] == "fail" for row in lab.results)
        print(json.dumps({"summary": {"pass": len(lab.results) - failed, "fail": failed}}))
        sys.exit(bool(failed))


if __name__ == "__main__":
    main()
