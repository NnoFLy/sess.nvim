#!/usr/bin/env python3
"""Disposable tmux 3.8 primitive probes, not a Sess implementation.

Every server command names an exclusive private socket. No normal tmux server,
user environment, or pane capture is used. Only synthetic fixture PIDs are killed.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import tempfile
import time

TMUX = "/usr/sbin/tmux"
PYTHON = "/usr/sbin/python3"
RESULTS = []


def record(case, outcome, **observed):
    RESULTS.append(dict(case=case, outcome=outcome, observed=observed))


def identity(pid):
    try:
        with open(f"/proc/{pid}/stat") as stream:
            fields = stream.read(4096).rsplit(")", 1)[1].split()
        return (fields[19], fields[0])  # Linux field 22, state
    except (FileNotFoundError, ProcessLookupError):
        return None


def live(pid, start):
    current = identity(pid)
    return current is not None and current[0] == start and current[1] != "Z"


def until(fn, seconds=2):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(0.01)  # Observation polling, never the atomicity oracle.
    return False


def quoted(value):
    # tmux source-file literals, not shell quoting. Fixtures prohibit newlines.
    assert "\n" not in value and "\r" not in value
    return "'" + value.replace("'", "'\\''") + "'"


class Server:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sess-native-")
        self.root = Path(self.temp.name)
        assert self.root.stat().st_mode & 0o777 == 0o700
        self.socket = str(self.root / "socket")
        self.env = {"HOME": str(self.root), "PATH": "/usr/bin:/bin", "TERM": "xterm-256color",
                    "XDG_CONFIG_HOME": str(self.root / "config"), "SHELL": "/bin/sh", "LC_ALL": "C"}
        self.config = self.root / "tmux.conf"
        self.config.write_text("set -g exit-empty off\nset -g exit-unattached off\n"
                               "set -g destroy-unattached off\nset -g default-shell /bin/sh\n"
                               "set -g status off\nset -s @generation G1\n")
        self.fixture = self.root / "fixture.py"
        self.fixture.write_text("import signal,sys,time\nfrom pathlib import Path\n"
                                "if sys.argv[1]=='ignore': signal.signal(signal.SIGHUP,signal.SIG_IGN)\n"
                                "Path(sys.argv[2]).touch()\nwhile True: time.sleep(1)\n")
        self.pids = []
        self.clients = []
        self.serial = 0
        self.call("new-session", "-d", "-s", "anchor", PYTHON, str(self.fixture), "normal", str(self.root / "initial"), start=True)
        self.anchor = self.call("display-message", "-p", "-t", "anchor", "#{session_id}").stdout.strip()
        self.call("set", "-t", self.anchor, "@owner", "O1")
        self.call("set", "-t", self.anchor, "@incarnation", "I1")
        self.call("set", "-t", self.anchor, "@context", "C1")
        self.call("set", "-t", self.anchor, "@role", "anchor")
        self.track(self.anchor + ":")

    def call(self, *args, text=None, start=False, raw=False):
        cmd = [TMUX, "-S", self.socket]
        if start:
            cmd += ["-f", str(self.config)]
        else:
            cmd += ["-N"]
        if raw and text is not None:
            text = text.encode("utf-8")
        return subprocess.run(cmd + list(args), input=text, text=not raw, capture_output=True,
                              env=self.env, cwd=self.root, timeout=5)

    def source(self, text):
        return self.call("source-file", "-", text=text + "\n")

    def track(self, target):
        data = self.call("display-message", "-p", "-t", target,
                         "#{window_id} #{pane_id} #{pane_pid}").stdout.split()
        assert len(data) == 3, data
        wid, pane, pid = data
        pid = int(pid)
        start = until(lambda: identity(pid))
        assert start
        self.pids.append((pid, start[0]))
        return wid, pane, pid, start[0]

    def window(self, mode="normal"):
        self.serial += 1
        ready = self.root / f"ready{self.serial}"
        result = self.call("new-window", "-d", "-t", self.anchor + ":", "-P", "-F", "#{window_id}",
                           PYTHON, str(self.fixture), mode, str(ready))
        assert result.returncode == 0, result.stderr
        target = result.stdout.strip()
        data = self.track(target)
        assert until(ready.exists)
        return data

    def guard(self, target=None, generation="G1", role="anchor", **changes):
        expected = {"session_id": self.anchor if target is None else target, "@generation": generation,
                    "@owner": "O1", "@incarnation": "I1", "@context": "C1", "@role": role}
        expected.update(changes)
        for value in expected.values():
            assert re.fullmatch(r"[A-Za-z0-9_$@%.-]+", value), value
        terms = [f"#{{==:#{{{key}}},{value}}}" for key, value in expected.items()]
        while len(terms) > 1:
            terms = [f"#{{&&:{terms[0]},{terms[1]}}}"] + terms[2:]
        return terms[0]

    def conditional(self, guard, yes, target=None):
        return self.source(f"if-shell -F -t {quoted(target or self.anchor)} {quoted(guard)} {{ {yes} }} {{ display-message -p REJECT }}")

    def presentation(self):
        result = self.conditional(self.guard(), f"new-session -d -t {quoted(self.anchor)} -P -F 'PRESENT=#{{session_id}}'")
        assert result.returncode == 0 and re.fullmatch(r"PRESENT=\$[0-9]+\n", result.stdout), result.stderr
        target = result.stdout.strip().split("=", 1)[1]
        for key, value in (("@owner", "O1"), ("@incarnation", "I1"), ("@context", "C1"), ("@role", "presentation")):
            self.call("set", "-t", target, key, value)
        return target

    def attach(self, target, guard):
        # Same native recipe as source-file -, using a private file so stdin is a PTY.
        path = self.root / "attach.conf"
        path.write_text(f"if-shell -F -t {quoted(target)} {quoted(guard)} {{ attach-session -E -t {quoted(target)} }} {{ display-message -p REJECT }}\n")
        child, fd = pty.fork()
        if child == 0:
            os.chdir(self.root)
            os.execve(TMUX, [TMUX, "-N", "-S", self.socket, "source-file", str(path)], self.env)
        self.clients.append((child, fd))
        # Bound/discard only synthetic terminal bytes; assert state using list-clients.
        def attached():
            rows = self.call("list-clients", "-F", "#{client_pid} #{session_id}").stdout.splitlines()
            return f"{child} {target}" in rows
        success = until(attached, 0.5)
        if not success:
            def exited():
                state = identity(child)
                return state is None or state[1] == "Z"
            assert until(exited), "refused attachment client did not exit"
        captured = 0
        if select.select([fd], [], [], 0)[0]:
            try:
                captured = len(os.read(fd, 8192))
            except OSError:
                pass
        return success, captured

    def close(self):
        self.call("kill-server")  # Only this class's private disposable endpoint.
        for pid, start in self.pids:
            if live(pid, start):
                os.kill(pid, signal.SIGKILL)
        for child, fd in self.clients:
            try:
                os.kill(child, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.close(fd)
            os.waitpid(child, 0)
        for pid, start in self.pids:
            assert until(lambda: not live(pid, start)), "synthetic process cleanup failed"
        self.temp.cleanup()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def check_output(value):
    # Validate transport bytes before decoding or universal-newline conversion.
    return re.fullmatch(rb"PRESENT=\$[0-9]+\n", value) is not None


def creation_attachment():
    with Server() as s:
        pres = s.presentation()
        before = s.call("list-windows", "-t", s.anchor, "-F", "#{window_id} #{pane_id} #{pane_pid}").stdout
        after = s.call("list-windows", "-t", pres, "-F", "#{window_id} #{pane_id} #{pane_pid}").stdout
        assert before == after
        record("A01-grouped-creation", "pass", shared_exact_ids=True, retained_windows=len(after.splitlines()), transient_shell="accepted; not directly measured")
        ok, count = s.attach(pres, s.guard(target=pres, role="presentation"))
        assert ok
        record("A02-guarded-real-PTY-attach", "pass", attached_exact_presentation=ok, discarded_pty_bytes=count)
        s.call("set", "-s", "@generation", "G2")
        ok, _ = s.attach(pres, s.guard(target=pres, role="presentation"))
        assert not ok
        # Verify refusal preserves the already attached first client.
        clients = s.call("list-clients", "-F", "#{session_id}").stdout.splitlines()
        assert len(clients) == 1
        record("A03-stale-generation-attach", "pass", original_client_only=True)
    with Server() as s:
        for key in ("@generation", "@owner", "@incarnation", "@context", "@role"):
            scope = ["-s"] if key == "@generation" else ["-t", s.anchor]
            saved = s.call("show", *scope, "-v", key).stdout.strip()
            s.call("set", *scope, key, "")
            result = s.conditional(s.guard(), f"new-session -d -t {quoted(s.anchor)} -P -F 'PRESENT=#{{session_id}}'")
            assert result.stdout == "REJECT\n" and result.returncode == 0
            s.call("set", *scope, key, saved)
        record("A04-empty-markers", "pass", rejected=5, rejection_exit_status=0)
        # A real attached client supplies the fallback format context.
        assert s.attach(s.anchor, s.guard())[0]
        # Missing target fallback: marker-only false positive, exact-ID negative control.
        fallback = s.conditional("#{==:#{@owner},O1}", "display-message -p ACCEPT", target="$999999")
        exact = s.conditional(s.guard(target="$999999"), "display-message -p ACCEPT", target="$999999")
        assert fallback.stdout == "ACCEPT\n" and exact.stdout == "REJECT\n"
        record("A05-fallback-resolution", "pass", marker_only_wrongly_accepts=True, exact_id_rejects=True)
        s.call("rename-session", "-t", s.anchor, "renamed")
        assert s.conditional(s.guard(), "display-message -p ACCEPT").stdout == "ACCEPT\n"
        record("A06-rename", "pass", exact_anchor_survives_rename=True)
        s.call("set", "-t", s.anchor, "@owner", "WRONG")
        assert s.conditional(s.guard(), "display-message -p ACCEPT").stdout == "REJECT\n"
        record("A07-wrong-owner", "pass", refused=True)
    with Server() as s:
        old = s.anchor
        s.call("kill-session", "-t", old)
        # Deliberately unsafe negative control; exhibits a new group on missing target.
        unsafe = s.call("new-session", "-d", "-t", old, "-P", "-F", "#{session_id}")
        assert unsafe.returncode == 0 and unsafe.stdout.strip() != old
        record("A08-unguarded-missing-target", "fail", creates_unrelated_group=True, negative_control=True)
        guarded = s.conditional(s.guard(), "new-session -d -t '$0'")
        assert guarded.stdout == "REJECT\n"
        record("A09-guarded-missing-anchor", "pass", refuses_after_id_disappearance=True)
    with Server() as s:
        old_guard = s.guard()
        old = s.anchor
        s.call("kill-server")
        s.call("new-session", "-d", "-s", "replacement", "sleep", "60", start=True)
        replacement = s.call("display-message", "-p", "-t", "replacement", "#{session_id}").stdout.strip()
        s.track(replacement + ":")
        assert replacement == old
        s.call("set", "-s", "@generation", "G2")
        # Matching owner markers intentionally remove them as an independent reason to reject.
        for key, value in (("@owner", "O1"), ("@incarnation", "I1"), ("@context", "C1"), ("@role", "anchor")):
            s.call("set", "-t", replacement, key, value)
        result = s.conditional(old_guard, "new-session -d -t '$0'")
        assert result.stdout == "REJECT\n"
        ok, _ = s.attach(replacement, old_guard)
        assert not ok
        record("A10-cross-invocation-replacement", "pass", reused_session_id=True, stale_creation_and_attach_refused=True)
    with Server() as s:
        pres = s.presentation()
        s.call("kill-session", "-t", s.anchor)
        assert s.call("has-session", "-t", pres).returncode == 0
        # Negative control: presentation markers alone do not prove a canonical
        # anchor remains. This is deliberately NOT the complete approved guard.
        result = s.conditional(s.guard(target=pres, role="presentation"), "display-message -p ACCEPT", target=pres)
        assert result.stdout == "ACCEPT\n"
        record("A11-presentation-only-guard", "fail", surviving_presentation_accepts_without_anchor=True,
               negative_control=True, limitation="complete dual anchor/presentation membership guard unqualified")


def epochs_and_stop():
    with Server() as s:
        s.call("set-hook", "-g", "pane-created", "set-option -pF @epoch '#{hook_pane}N#{hook_created_respawn}'")
        wid, pane, pid, start = s.window()
        assert until(lambda: s.call("show", "-p", "-t", pane, "-v", "@epoch").stdout.strip())
        old_epoch = s.call("show", "-p", "-t", pane, "-v", "@epoch").stdout.strip()
        # In a single client queue, pane-created is queued globally, not inline.
        result = s.source(f"respawn-pane -k -t {quoted(pane)} {PYTHON} {quoted(str(s.fixture))} normal {quoted(str(s.root / 'respawn-ready'))}\n"
                          f"display-message -p -t {quoted(pane)} 'EPOCH=#{{@epoch}} PID=#{{pane_pid}}'\n")
        new = s.track(pane)
        later = s.call("show", "-p", "-t", pane, "-v", "@epoch").stdout.strip()
        stale_inside = f"EPOCH={old_epoch} " in result.stdout
        assert stale_inside and later != old_epoch and new[2] != pid
        record("S01-respawn-epoch-ordering", "fail", old_epoch_visible_in_respawn_queue=True, new_epoch_visible_next_invocation=True, pane_and_window_ids_unchanged=(wid, pane) == new[:2], pid_changed=True)
        # Native hook can stamp, but not before same-client subsequent admission.
        result = s.call("new-window", "-d", "-t", s.anchor + ":", "-P", "-F", "#{window_id} EPOCH=#{@epoch}",
                        PYTHON, str(s.fixture), "normal", str(s.root / "create-ready"))
        created_window = result.stdout.split()[0]
        s.track(created_window)
        later_created = s.call("display-message", "-p", "-t", created_window, "#{@epoch}").stdout.strip()
        assert result.stdout.strip().endswith("EPOCH=") and later_created
        record("S02-creation-epoch-admission", "fail", creation_print_precedes_hook=True, later_stamp_nonempty=True,
               limitation="delayed admission could refuse unstamped panes; no unique epoch allocator qualified")
        # Expected PID/shape synchronous checks reject stale respawn consent.
        guard = f"#{{&&:{s.guard()},#{{&&:#{{==:#{{pane_id}},{pane}}},#{{==:#{{pane_pid}},{pid}}}}}}}"
        result = s.conditional(guard, f"kill-window -t {quoted(wid)}", target=s.anchor + ":" + wid)
        assert result.stdout == "REJECT\n" and live(new[2], new[3])
        record("S03-stale-PID-consent", "pass", replacement_preserved=True)
    with Server() as s:
        wid, pane, pid, start = s.window()
        guard = f"#{{&&:{s.guard()},#{{&&:#{{==:#{{window_panes}},1}},#{{&&:#{{==:#{{window_id}},{wid}}},#{{&&:#{{==:#{{pane_id}},{pane}}},#{{==:#{{pane_pid}},{pid}}}}}}}}}}}"
        result = s.conditional(guard, f"kill-window -t {quoted(wid)}", target=s.anchor + ":" + wid)
        assert result.returncode == 0 and until(lambda: not live(pid, start))
        assert s.call("display-message", "-p", "-t", pane, "#{pane_id}").stdout.strip() == ""
        record("S04-normal-root-stop", "pass", exact_window_removed=True, original_process_identity_terminated=True)
        wid, pane, pid, start = s.window("ignore")
        result = s.conditional(f"#{{&&:{s.guard()},#{{==:#{{pane_pid}},{pid}}}}}", f"kill-window -t {quoted(wid)}", target=s.anchor + ":" + wid)
        gone = s.call("display-message", "-p", "-t", pane, "#{pane_id}").stdout.strip() == ""
        survives = not until(lambda: not live(pid, start), 0.3)
        assert result.returncode == 0 and gone and survives
        record("S05-HUP-ignoring-root-stop", "fail", kill_window_exit_status=0, pane_removed=True, exact_root_still_running=True)
    with Server() as s:
        wid, pane, pid, start = s.window()
        s.call("split-window", "-d", "-t", pane, "sleep", "60")
        # Track both synthetic panes for cleanup.
        for p in s.call("list-panes", "-t", wid, "-F", "#{pane_id}").stdout.splitlines():
            s.track(p)
        result = s.conditional("#{==:#{window_panes},1}", f"kill-window -t {quoted(wid)}", target=s.anchor + ":" + wid)
        assert result.stdout == "REJECT\n" and live(pid, start)
        record("S06-multipane-preservation", "pass", shape_mismatch_refused=True)
    with Server() as s:
        wid, pane, pid, start = s.window()
        other = s.call("new-session", "-d", "-P", "-F", "#{session_id}", "sleep", "60").stdout.strip()
        s.track(other + ":")
        s.call("link-window", "-s", wid, "-t", other + ":")
        # This native count counts distinct groups and ungrouped sessions, not
        # grouped presentation links. No names are used as ownership evidence.
        result = s.conditional("#{==:#{window_linked_sessions},1}", f"kill-window -t {quoted(wid)}", target=s.anchor + ":" + wid)
        assert result.stdout == "REJECT\n" and live(pid, start)
        record("S07-cross-group-link", "pass", extra_group_link_refused=True)
        unavailable = s.call("display-message", "-p", "-t", pane, "#{pane_start_identity}").stdout
        assert unavailable == "\n"
        record("S08-native-process-start-identity", "blocked", proposed_format_unavailable=True,
               limitation="format table exposes pane_pid but no Linux /proc starttime/pidfd conditional stop primitive")


def fencing_and_races():
    with Server() as s:
        pres = s.presentation()
        window = s.track(s.anchor + ":")[0]
        s.call("kill-window", "-t", window)
        rows = s.call("list-sessions", "-F", "#{session_id}").stdout.splitlines()
        assert s.anchor not in rows and pres not in rows
        stale = s.call("new-window", "-d", "-t", pres + ":", "sleep", "60")
        assert stale.returncode != 0
        record("F01-last-window-fence", "pass", anchor_and_presentation_removed=True, exact_old_presentation_new_window_refused=True)
    with Server() as s:
        old = s.track(s.anchor + ":")[0]
        arrival = s.window()
        s.call("kill-window", "-t", old)
        assert live(arrival[2], arrival[3]) and s.call("has-session", "-t", s.anchor).returncode == 0
        record("F02-unconsented-arrival", "pass", new_window_survives=True, group_remains=True)
    with Server() as s:
        # Simultaneous native queues: only two legal serialized outcomes. Source,
        # not scheduling luck, establishes the non-yielding segment.
        counts = {"stop_first": 0, "mutation_first": 0}
        for i in range(40):
            wid, pane, pid, start = s.window()
            s.call("set", "-w", "-t", wid, "@consent", "yes")
            guard = f"#{{&&:#{{==:#{{window_id}},{wid}}},#{{==:#{{@consent}},yes}}}}"
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                a = pool.submit(s.conditional, guard, f"kill-window -t {quoted(wid)}", s.anchor + ":" + wid)
                b = pool.submit(s.call, "set", "-w", "-t", wid, "@consent", "no")
                stop = a.result()
                b.result()
            if stop.stdout == "REJECT\n":
                assert live(pid, start)
                counts["mutation_first"] += 1
                s.call("kill-window", "-t", wid)
            else:
                assert until(lambda: not live(pid, start))
                counts["stop_first"] += 1
        record("F03-native-marker-race", "pass", runs=40, counts=counts, limitation="no scheduling guarantee; source-backed subset only")
    counts = {"stop_first": 0, "arrival_first": 0}
    for i in range(20):
        with Server() as s:
            pres = s.presentation()
            wid = s.track(s.anchor + ":")[0]
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                stop = pool.submit(s.call, "kill-window", "-t", wid)
                arrival = pool.submit(s.call, "new-window", "-d", "-t", pres + ":", "-P", "-F", "#{window_id}", "sleep", "60")
                assert stop.result().returncode == 0
                result = arrival.result()
            if result.returncode == 0:
                new = s.track(result.stdout.strip())
                assert live(new[2], new[3])
                counts["arrival_first"] += 1
            else:
                assert s.call("has-session", "-t", s.anchor).returncode != 0
                counts["stop_first"] += 1
    record("F04-last-window-native-arrival-race", "pass", runs=20, counts=counts,
           limitation="window removal only; does not prove ignored-HUP process termination")
    with Server() as s, Server() as unrelated:
        sentinel = unrelated.track(unrelated.anchor + ":")
        victim = s.window()
        s.conditional(s.guard(), f"kill-window -t {quoted(victim[0])}")
        assert live(sentinel[2], sentinel[3]) and unrelated.call("has-session", "-t", unrelated.anchor).returncode == 0
        record("F05-unrelated-server", "pass", distinct_private_socket_sentinel_unchanged=True)


def parser():
    with Server() as s:
        sentinel = s.root / "injected"
        hostile = "#(touch " + str(sentinel) + ") #{session_id} ; display-message INJECTED ' \" \\"
        s.call("set", "-t", s.anchor, "@label", hostile)
        result = s.call("display-message", "-p", "-t", s.anchor, "#{@label}")
        assert result.stdout == hostile + "\n" and not sentinel.exists()
        # Comparisons are fixed expressions; marker value is never source code.
        result = s.conditional("#{==:#{@label},ordinary}", "display-message -p BAD")
        assert result.stdout == "REJECT\n" and not sentinel.exists()
        record("P01-nonrecursive-data", "pass", option_value_literal=True, fixed_guard_rejects_hostile_data=True,
               command_substitution_not_observed=True)
        s.call("rename-window", "-t", s.anchor + ":", hostile)
        result = s.call("display-message", "-p", "-t", s.anchor, "#{window_name}")
        assert result.stdout != hostile + "\n" and s.anchor in result.stdout
        record("P01b-raw-rename-argv", "fail", label_format_expanded=True,
               limitation="shell quoting and argv alone do not prevent tmux format expansion; #() execution not established here")
        s.call("rename-window", "-t", s.anchor + ":", hostile.replace("#", "##"))
        result = s.call("display-message", "-p", "-t", s.anchor, "#{window_name}")
        assert result.stdout == hostile.replace("\\", "\\\\") + "\n" and not sentinel.exists()
        record("P01c-escaped-rename", "pass", format_metacharacters_literal=True, backend_escapes_backslash=True)
        result = s.source("if-shell -F '1' { not-a-command } { display-message -p REJECT }")
        assert result.returncode != 0
        record("P02-parser-failure", "pass", rejected_unknown_command=True, exit_status=result.returncode)
        malformed = [b"", b"REJECT\n", b"PRESENT=$1\nPRESENT=$2\n", b"PRESENT=anchor\n", b"PRESENT=$1\nnoise\n", b"PRESENT=$1\r\n", b"PRESENT=$1\x00\n", b"PRESENT=$1;kill-server\n"]
        assert not any(check_output(x) for x in malformed) and check_output(b"PRESENT=$123\n")
        backend_cases = []
        emitter_cases = []
        for label, expected in (("exact-LF", b"PRESENT=$123\n"),
                                ("CRLF", b"PRESENT=$123\r\n"),
                                ("embedded-CR", b"PRESENT=$12\r3\n")):
            result = s.call("display-message", "-p", expected[:-1].decode("ascii"), raw=True)
            # This tmux output path sanitizes CR to underscore. Do not claim
            # rejection of real tmux-origin CR on the basis of this fixture.
            assert result.returncode == 0 and result.stdout == expected.replace(b"\r", b"_")
            accepted = check_output(result.stdout)
            assert accepted == (label == "exact-LF")
            backend_cases.append(dict(case=label, stdout_hex=result.stdout.hex(), accepted=accepted))
            # Real CR bytes via a synthetic emitter, explicitly not tmux output.
            cmd = [PYTHON, "-c", "import os,sys; os.write(1,bytes.fromhex(sys.argv[1]))", expected.hex()]
            emitted = subprocess.run(cmd, capture_output=True, env=s.env, cwd=s.root, timeout=5)
            assert emitted.returncode == 0 and emitted.stdout == expected
            assert check_output(emitted.stdout) == (label == "exact-LF")
            emitter_cases.append(dict(case=label, stdout_hex=emitted.stdout.hex(), accepted=check_output(emitted.stdout)))
            if label == "CRLF":
                normalized = subprocess.run(cmd, text=True, capture_output=True, env=s.env, cwd=s.root, timeout=5)
                assert normalized.returncode == 0 and normalized.stdout == "PRESENT=$123\n"
                assert check_output(normalized.stdout.encode("ascii"))
        record("P03-output-oracle", "pass", rejected_synthetic_malformed=len(malformed),
               synthetic_positive_controls=1, backend_cases=backend_cases, synthetic_emitter_cases=emitter_cases,
               text_mode_wrongly_accepts_CRLF=True,
               limitation="tmux sanitized attempted CR to underscore; tmux-origin CR and external consumer integration remain untested")
        # Whole-input parse failure precedes execution; runtime command errors
        # do not roll back earlier commands. Neither is successful presentation output.
        result = s.source("set -s @partial committed\nnot-a-command\n")
        value = s.call("show", "-s", "-v", "@partial").stdout.strip()
        assert result.returncode != 0 and value != "committed"
        runtime = s.source("set -s @partial committed\nkill-window -t '@999999'\n")
        value = s.call("show", "-s", "-v", "@partial").stdout.strip()
        assert runtime.returncode != 0 and value == "committed"
        record("P04-parser-vs-runtime-error", "pass", parse_error_exit=result.returncode, parse_error_has_no_earlier_effect=True,
               runtime_error_exit=runtime.returncode, runtime_error_retains_earlier_effect=True)
        invalid = [("empty", ""), ("command", "$1;kill-server"),
                   ("newline", "$1\nkill-server"), ("format", "#{session_id}"),
                   ("job", "#(touch x)"), ("quote", "'"), ("space", " "), ("ESC", "\x1b")]
        assert invalid[2][1][2] == "\n" and invalid[7][1] == "\x1b"
        rejected = []
        # Change one field at a time; the other retains its valid default.
        for field in ("target", "generation"):
            for label, token in invalid:
                try:
                    s.guard(**{field: token})
                except AssertionError:
                    rejected.append(f"{field}:{label}")
                else:
                    raise AssertionError(f"accepted invalid {field}:{label}")
        assert len(rejected) == 2 * len(invalid)
        default_guard = s.guard()
        assert default_guard == s.guard(target=s.anchor, generation="G1")
        assert s.guard(target="$123", generation="G2") != default_guard
        record("P05-constrained-token-oracle", "pass", rejected_independent_fields=rejected,
               actual_newline_codepoint=ord(invalid[2][1][2]), actual_ESC_codepoint=ord(invalid[7][1]),
               valid_default_and_explicit_controls=True, valid_alternate_control=True,
               limitation="probe construction only, before backend invocation; not an implementation adapter")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--parser-only", action="store_true", help="run only the bounded P-series subset")
    args = cli.parse_args()
    if not args.parser_only:
        creation_attachment()
        epochs_and_stop()
        fencing_and_races()
    parser()
    print(json.dumps({"schema": 1, "scope": "parser-only" if args.parser_only else "full-probe",
                      "tmux": subprocess.check_output([TMUX, "-V"], text=True).strip(), "cases": RESULTS}, indent=2))
