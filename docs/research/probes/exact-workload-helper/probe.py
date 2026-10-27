#!/usr/bin/env python3
"""Disposable counterexamples, NOT a termination implementation.

Only private tmux sockets, synthetic workloads and acquired pidfds are used.
No /proc enumeration, broad PID signals, user environment capture or installs.
"""
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def proc_read(pid, name):
    with Path(f"/proc/{pid}/{name}").open("rb") as stream:
        data = stream.read(4097)
    if len(data) > 4096:
        raise ValueError("oversize synthetic process record")
    return data


def stat(pid):
    # Read just a positively owned fixture identity; never enumerate /proc.
    text = proc_read(pid, "stat")
    fields = text[text.rindex(b")") + 2 :].split()
    return {"state": fields[0].decode(), "ppid": int(fields[1]),
            "pgrp": int(fields[2]), "session": int(fields[3]),
            "start": int(fields[19])}


def wait_for(predicate, seconds=4):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.01)  # readiness/postconditions, not an exclusion argument
    raise TimeoutError("synthetic fixture readiness/postcondition deadline")


def publish(path):
    Path(path).write_text(json.dumps({"pid": os.getpid(), **stat(os.getpid())}))


def fixture(mode, path):
    signal.alarm(30)  # safety bound even if harness crashes
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    if mode == "tree":
        child = os.fork()
        if child == 0:
            os.setsid()  # detached descendant, no common root process group
            fd = os.open(os.devnull, os.O_RDWR)
            for target in (0, 1, 2):
                os.dup2(fd, target)
            if fd > 2:
                os.close(fd)
            signal.alarm(30)  # fork does not inherit the parent's alarm
            publish(path + ".child")
            while True:
                signal.pause()
        publish(path)
        wait_for(lambda: Path(path + ".exit").exists(), 20)
        os._exit(0)
    publish(path)
    while True:
        signal.pause()


def helper_barrier(ready, release):
    signal.alarm(20)
    Path(ready).touch()
    wait_for(lambda: Path(release).exists(), 15)


def exited(fd):
    return bool(select.select([fd], [], [], 0)[0])


class InjectedFailure(RuntimeError):
    """An intentional probe-cleanup fault, not a backend success/failure."""


def watchdog(fd, ready):
    # The inherited pidfd is the ONLY signal authority. Once this watchdog is
    # running, harness loss leaves the server bounded; no target lookup is used.
    signal.alarm(50)
    Path(ready).touch()
    if not select.select([fd], [], [], 45)[0]:
        signal.pidfd_send_signal(fd, signal.SIGKILL)
        wait_for(lambda: exited(fd))


class Harness:
    def __init__(self, fault=None):
        self.root = None
        self.server = None
        self.serverfd = None
        self.guard = None
        self.identities = []
        self.clients = []
        self.pending_births = set()
        self.cleanup_events = []
        self.cleanup_complete = False
        self.fault = fault

    def __enter__(self):
        try:
            # Required by unreaped-child pidfd acquisition: no SIGCHLD ignore or
            # custom reaper. This standalone script installs neither nor threads.
            if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
                raise RuntimeError("unsupported SIGCHLD disposition")
            # No destructor may unlink the socket/evidence on ambiguous exit.
            self.root = Path(tempfile.mkdtemp(prefix="sess-exact-"))
            assert self.root.stat().st_mode & 0o777 == 0o700
            self.home = self.root / "home"
            self.home.mkdir(mode=0o700)
            self.socket = self.root / "s"
            self.env = {"HOME": str(self.home), "PATH": "/usr/bin:/bin",
                        "TERM": "xterm", "SHELL": "/bin/sh", "LC_ALL": "C",
                        "XDG_CONFIG_HOME": str(self.home)}
            self.script = Path(__file__).resolve()
            self.python = str(Path(sys.executable).resolve())
            self.tmux = "/usr/bin/tmux"
            config = self.root / "tmux.conf"
            config.write_text("set -g exit-empty off\nset -g exit-unattached off\n"
                              "set -g destroy-unattached off\nset -g default-shell /bin/sh\n"
                              "set -g status off\nset -g remain-on-exit on\n")
            # Pinned -D semantics: no daemon fork and no command argument.
            # Keep this direct child unreaped until pidfd acquisition; startup
            # timeouts cannot lose its ownership behind a daemonized child.
            self.server = subprocess.Popen(
                [self.tmux, "-D", "-S", str(self.socket), "-f", str(config)],
                env=self.env, cwd=self.home, stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.serverfd = os.pidfd_open(self.server.pid)
            guard_ready = self.root / "watchdog-ready"
            self.guard = subprocess.Popen(
                [self.python, str(self.script), "--watchdog", str(self.serverfd), str(guard_ready)],
                pass_fds=(self.serverfd,), env=self.env, cwd=self.home,
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL)
            wait_for(guard_ready.exists)
            wait_for(lambda: self.socket.exists() or exited(self.serverfd))
            assert not exited(self.serverfd), "foreground synthetic server exited at startup"
            assert self.call("display-message", "-p", "#{pid}") == str(self.server.pid)
            initial = self.root / "initial"
            self.call("new-session", "-d", "-s", "fixture", *self.command("hold", initial))
            self.track(initial)
            if self.fault == "setup-after-session":
                raise InjectedFailure("setup after synthetic session creation")
            self.call("set-hook", "-g", "pane-created",
                      "set-option -pF @epoch '#{hook_pane}N#{hook_created_respawn}'")
            return self
        except BaseException as setup_error:
            try:
                self.cleanup()
            except BaseException as cleanup_error:
                raise BaseExceptionGroup("setup and cleanup errors", [setup_error, cleanup_error])
            raise

    def argv(self, *args):
        return [self.tmux, "-N", "-S", str(self.socket), *args]

    def call(self, *args):
        return subprocess.run(self.argv(*args), env=self.env, cwd=self.home,
                              capture_output=True, text=True, timeout=5,
                              check=True).stdout.strip()

    def command(self, mode, ready):
        self.pending_births.add(ready)
        if mode == "tree":
            self.pending_births.add(Path(str(ready) + ".child"))
        return [self.python, str(self.script), "--fixture", mode, str(ready)]

    def track(self, ready):
        wait_for(lambda: ready.exists() and ready.stat().st_size)
        data = json.loads(ready.read_text())
        # Fixtures remain alive at this barrier. This is test ownership, NOT an
        # arbitrary-process acquisition algorithm or proof against hostile peers.
        before = stat(data["pid"])
        assert before["start"] == data["start"] and before["state"] != "Z"
        fd = os.pidfd_open(data["pid"])
        self.identities.append(fd)
        assert stat(data["pid"])["start"] == data["start"] and not exited(fd)
        self.pending_births.discard(ready)
        return data, fd

    def window(self, label, mode="hold"):
        ready = self.root / label
        target = self.call("new-window", "-d", "-t", "=fixture:", "-P", "-F",
                           "#{window_id} #{pane_id}", *self.command(mode, ready)).split()
        return target, ready, self.track(ready)

    @staticmethod
    def stop_fd(fd):
        if not exited(fd):
            try:
                signal.pidfd_send_signal(fd, signal.SIGKILL)
            except ProcessLookupError:
                pass

    @staticmethod
    def stop_child(child):
        if child.poll() is None:
            child.kill()  # positively owned, unreaped Popen child only

    def drain_client(self, client):
        if self.fault == "client-drain":
            self.fault = None
            raise InjectedFailure("first client drain")
        client.communicate(timeout=5)

    def cleanup(self):
        errors = []

        def attempt(label, operation):
            try:
                value = operation()
                self.cleanup_events.append({"step": label, "result": "passed"})
                return True, value
            except BaseException as error:
                errors.append(error)
                self.cleanup_events.append({"step": label, "result": "failed",
                                            "error_type": type(error).__name__})
                return False, None

        # Each operation is independent: a failed signal/drain/wait must not
        # suppress later identities, clients, server or watchdog handling.
        for i, fd in enumerate(self.identities):
            attempt(f"fixture-{i}-signal", lambda fd=fd: self.stop_fd(fd))
        clients_done = True
        for i, client in enumerate(self.clients):
            attempt(f"client-{i}-stop", lambda client=client: self.stop_child(client))
            attempt(f"client-{i}-drain", lambda client=client: self.drain_client(client))
            ok, _ = attempt(f"client-{i}-wait", lambda client=client: client.wait(timeout=5))
            clients_done &= ok
        server_done = self.server is None
        if self.server is not None:
            if self.serverfd is not None:
                attempt("server-pidfd-signal", lambda: self.stop_fd(self.serverfd))
            # Also covers setup failing before pidfd/watchdog acquisition. This
            # never looks up a target by socket or signals an arbitrary PID.
            attempt("server-direct-child-stop", lambda: self.stop_child(self.server))
            server_done, _ = attempt("server-wait", lambda: self.server.wait(timeout=5))
            if self.serverfd is not None:
                ok, dead = attempt("server-pidfd-exit", lambda: exited(self.serverfd))
                server_done = server_done and ok and dead
        fixtures_done = True
        for i, fd in enumerate(tuple(self.identities)):
            ok, _ = attempt(f"fixture-{i}-exit", lambda fd=fd: wait_for(lambda: exited(fd)))
            fixtures_done &= ok
            if ok:
                closed, _ = attempt(f"fixture-{i}-close", lambda fd=fd: os.close(fd))
                if closed:
                    self.identities.remove(fd)
        guard_done = self.guard is None
        if self.guard is not None and server_done:
            guard_done, _ = attempt("watchdog-wait", lambda: self.guard.wait(timeout=5))
            if not guard_done:
                attempt("watchdog-direct-child-stop", lambda: self.stop_child(self.guard))
                guard_done, _ = attempt("watchdog-final-wait", lambda: self.guard.wait(timeout=5))
        # Do NOT terminate the watchdog while server exit remains ambiguous.
        known_done = server_done and fixtures_done and clients_done and guard_done
        if known_done and not self.pending_births:
            if self.serverfd is not None:
                ok, _ = attempt("server-pidfd-close", lambda: os.close(self.serverfd))
                if ok:
                    self.serverfd = None
            if self.root is not None:
                ok, _ = attempt("private-directory-remove", lambda: shutil.rmtree(self.root))
                self.cleanup_complete = ok
            else:
                self.cleanup_complete = True
        else:
            errors.append(RuntimeError("owned exit/birth status ambiguous; private evidence retained"))
            self.cleanup_events.append({"step": "private-directory-remove", "result": "blocked"})
        if errors:
            raise BaseExceptionGroup("synthetic cleanup errors", errors)

    def __exit__(self, _type, body_error, _traceback):
        try:
            self.cleanup()
        except BaseException as cleanup_error:
            if body_error is not None:
                raise BaseExceptionGroup("probe and cleanup errors", [body_error, cleanup_error])
            raise


def main():
    results = []
    with Harness() as h:
        # Historical descendants are already unlinked before a stop-time helper
        # could inspect this pane. Only the fixture oracle supplies the child PID.
        (window, pane), ready, (root, rootfd) = h.window("tree", "tree")
        child, childfd = h.track(Path(str(ready) + ".child"))
        (_, _), _, (sentinel, sentinelfd) = h.window("unrelated")
        child_before = stat(child["pid"])
        assert child_before["pgrp"] != root["pgrp"]
        assert child_before["session"] != root["session"]
        cgroup = lambda pid: proc_read(pid, "cgroup")
        shared = cgroup(child["pid"]) == cgroup(root["pid"]) == cgroup(sentinel["pid"])
        assert shared
        Path(str(ready) + ".exit").touch()
        wait_for(lambda: exited(rootfd))
        wait_for(lambda: stat(child["pid"])["ppid"] != root["pid"])
        assert not exited(childfd)
        h.call("kill-window", "-t", window)
        assert not exited(childfd) and not exited(sentinelfd)
        results.append({"case": "D1-root-exit-detached-descendant", "status": "fail",
                        "observed": {"root_exit_witnessed": True, "reparented": True,
                                     "different_pgrp_and_session": True,
                                     "descendant_survives_window_removal": True,
                                     "unrelated_sentinel_survives": True}})
        results.append({"case": "C1-inherited-cgroup-not-workload-boundary", "status": "fail",
                        "observed": {"root_descendant_and_other_workload_share_cgroup": shared},
                        "scope": "No cgroup writes, enumeration, freeze or kill attempted"})

        # Native respawn inside one queue observes old hook stamp, deterministically.
        (window, pane), _, (old, oldfd) = h.window("old")
        epoch = h.call("show-options", "-p", "-t", pane, "-v", "@epoch")
        new_ready = h.root / "replacement"
        commands = ("respawn-pane -k -t " + shlex.quote(pane) + " " +
                    shlex.join(h.command("hold", new_ready)) + "\n" +
                    "display-message -p -t " + shlex.quote(pane) +
                    " 'EPOCH=#{@epoch} PID=#{pane_pid}'\n")
        source = h.root / "respawn.conf"
        source.write_text(commands)
        inside = h.call("source-file", str(source))
        new, newfd = h.track(new_ready)
        later = h.call("show-options", "-p", "-t", pane, "-v", "@epoch")
        assert "EPOCH=" + epoch + " " in inside and later != epoch
        assert old["pid"] != new["pid"] and not exited(newfd)
        # A real lifetime handle can signal only the old root, not replacement.
        signal.pidfd_send_signal(oldfd, signal.SIGTERM)
        wait_for(lambda: exited(oldfd))
        assert not exited(newfd)
        results.append({"case": "E1-respawn-before-hook", "status": "fail",
                        "observed": {"old_stamp_in_respawn_queue": True,
                                     "changed_stamp_next_call": True, "new_root_survives": True}})
        results.append({"case": "P1-pidfd-individual-lifetime", "status": "pass",
                        "observed": {"old_root_exit_witnessed": True,
                                     "replacement_and_unrelated_survive": not exited(sentinelfd)},
                        "scope": "No actual PID reuse forced; not complete tmux identity"})

        # External helper waits only its command queue, not all native clients.
        barrier, release = h.root / "barrier", h.root / "release"
        command = shlex.join([h.python, str(h.script), "--barrier", str(barrier), str(release)])
        client = subprocess.Popen(h.argv("run-shell", command), env=h.env, cwd=h.home,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        h.clients.append(client)
        wait_for(barrier.exists)
        assert client.poll() is None
        arrival, _, (_, arrivalfd) = h.window("native-arrival")
        assert client.poll() is None and not exited(arrivalfd)
        release.touch()
        out, err = client.communicate(timeout=5)
        assert client.returncode == 0 and not out and not err
        results.append({"case": "Q1-helper-wait-allows-native-arrival", "status": "fail",
                        "observed": {"other_client_created_workload_while_helper_waited": True}})

        # Known synthetic effect + lost acknowledgement, NOT a recovery protocol.
        _, _, (_, victimfd) = h.window("crash-victim")
        crash_code = ("import os,signal; signal.pidfd_send_signal(int(__import__('sys').argv[1]),"
                      "signal.SIGTERM); os.kill(os.getpid(),signal.SIGKILL)")
        childproc = subprocess.Popen([h.python, "-c", crash_code, str(victimfd)],
                                     pass_fds=(victimfd,), env=h.env, cwd=h.home,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        h.clients.append(childproc)
        out, err = childproc.communicate(timeout=5)
        wait_for(lambda: exited(victimfd))
        assert childproc.returncode == -signal.SIGKILL and not out and not err
        assert not exited(newfd) and not exited(sentinelfd) and not exited(arrivalfd)
        results.append({"case": "X1-effect-before-helper-crash", "status": "pass",
                        "observed": {"effect_witnessed_by_test_oracle": True,
                                     "helper_died_without_ack": True,
                                     "unrelated_and_replacement_survive": True},
                        "scope": "No production pending-effect persistence or retry protocol tested"})
    assert h.cleanup_complete and not h.identities and not h.pending_births
    print(json.dumps({"harness": "expected-counterexamples-observed", "runs": 1,
                      "results": results, "cleanup": cleanup_summary(h)}, indent=2))


def cleanup_summary(h):
    return {"foreground_server_exit_verified": h.server.returncode is not None,
            "watchdog_exit_status": h.guard.returncode,
            "tracked_fixture_handles_closed": not h.identities,
            "all_direct_clients_reaped": all(c.returncode is not None for c in h.clients),
            "no_pending_births": not h.pending_births,
            "private_directory_removed_after_known_exits": h.cleanup_complete and not h.root.exists()}


def cleanup_faults():
    results = []
    h = Harness(fault="setup-after-session")
    try:
        with h:
            raise AssertionError("setup fault did not fire")
    except InjectedFailure:
        pass
    assert h.cleanup_complete and not h.identities and h.server.returncode is not None
    assert h.guard.returncode == 0
    results.append({"case": "F1-setup-after-session", "status": "pass",
                    "observed": {"setup_error_surfaced": True,
                                 "enter_invoked_cleanup": True},
                    "cleanup": cleanup_summary(h)})

    h = Harness(fault="client-drain")
    try:
        with h:
            for label in ("client-a", "client-b"):
                ready = h.root / label
                client = subprocess.Popen(h.command("hold", ready), env=h.env, cwd=h.home,
                                          stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                          stderr=subprocess.DEVNULL)
                h.clients.append(client)
                h.track(ready)
    except BaseExceptionGroup as errors:
        assert len(errors.exceptions) == 1 and isinstance(errors.exceptions[0], InjectedFailure)
    else:
        raise AssertionError("teardown error was suppressed")
    steps = {event["step"]: event["result"] for event in h.cleanup_events}
    assert steps["client-0-drain"] == "failed"
    assert all(steps[label] == "passed" for label in
               ("client-0-wait", "client-1-drain", "client-1-wait", "server-wait",
                "server-pidfd-exit", "watchdog-wait", "private-directory-remove"))
    assert h.cleanup_complete and not h.identities and h.guard.returncode == 0
    results.append({"case": "F2-first-client-drain-error", "status": "pass",
                    "observed": {"injected_error_surfaced": True,
                                 "same_client_wait_still_attempted": True,
                                 "second_client_and_server_cleanup_continued": True},
                    "cleanup": cleanup_summary(h)})
    print(json.dumps({"suite": "cleanup-faults-only", "runs": 1, "results": results,
                      "scope": "Two writer-run exceptional paths, not all crash/timeout schedules"}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fixture":
        fixture(sys.argv[2], sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == "--barrier":
        helper_barrier(sys.argv[2], sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == "--watchdog":
        watchdog(int(sys.argv[2]), sys.argv[3])
    elif len(sys.argv) > 1 and sys.argv[1] == "--cleanup-faults":
        cleanup_faults()
    else:
        main()
