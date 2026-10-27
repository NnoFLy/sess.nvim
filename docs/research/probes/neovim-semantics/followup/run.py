#!/usr/bin/python3
"""Disposable C/Unix-socket qualification; never a Sess or product helper.

Run under the global heavy queue. All subprocess environments are synthetic.
No request/environment dump, payload file, default tmux server, installation,
trace observer, retry or retained workload output is used.
"""
import array
import errno
import hashlib
import json
import os
from pathlib import Path
import resource
import select
import socket as unix_socket
import struct
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
RESULTS = []
CAP = 8 * 1024 * 1024
OP = 741


def check(case, got, expected):
    RESULTS.append(dict(id=case, status="pass" if got == expected else "fail",
                        expected=expected, got=got))


def call(argv, env, **kw):
    return subprocess.run(argv, env=env, capture_output=True, timeout=12, **kw)


def frame(cwd, argv, env=(), mode=2, flags=1, op=OP):
    parts = [os.fsencode(cwd), *map(os.fsencode, argv), *map(os.fsencode, env)]
    body = b"".join(struct.pack("!I", len(s)) + s for s in parts)
    return struct.pack("!4s6I", b"SF01", 28 + len(body), len(argv), len(env), mode, op, flags) + body


def environment(snapshot, overrides):
    """Fixture-only contract constructor, not an implementation of the Sess API."""
    result = dict(snapshot)
    for key, value in overrides.items():
        if not isinstance(key, bytes) or not key or b"=" in key or b"\0" in key:
            raise ValueError("invalid name")
        if key in (b"TMUX", b"TMUX_PANE"):
            raise ValueError("reserved name")
        if value is False:
            result.pop(key, None)
        elif isinstance(value, bytes) and b"\0" not in value:
            result[key] = value
        else:
            raise ValueError("invalid value type")
    result.pop(b"TMUX", None)
    result.pop(b"TMUX_PANE", None)
    default_term = b"TERM" not in overrides
    if default_term:
        result.pop(b"TERM", None)
    return [key + b"=" + value for key, value in result.items()], int(default_term)


def line(proc, seconds=7):
    if not select.select([proc.stdout], [], [], seconds)[0]:
        raise RuntimeError("fixture synchronization deadline")
    return proc.stdout.readline().decode().strip()


def main(root):
    # No inherited environment, including loader/startup-sensitive variables.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    for name in ("home", "runtime", "config", "data", "state", "cache", "invoke", "placed"):
        (root / name).mkdir(mode=0o700)
    for name in ("invoke", "placed"):
        (root / name / "bin").mkdir(mode=0o700)
        script = root / name / "bin/pick"
        script.write_text("printf '" + ("INVOKING" if name == "invoke" else "WRONG") + ":%s\\n' \"$1\"\n")
        script.chmod(0o700)  # Intentionally no shebang: ENOEXEC control.
    env = dict(PATH="/usr/bin:/bin", HOME=str(root / "home"), LANG="C.UTF-8",
               XDG_RUNTIME_DIR=str(root / "runtime"), XDG_CONFIG_HOME=str(root / "config"),
               XDG_DATA_HOME=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
               XDG_CACHE_HOME=str(root / "cache"), TMPDIR=str(root), TERM="xterm-256color")
    version = call(["/usr/bin/nvim", "--version"], env).stdout.decode().splitlines()[:3]
    if version[0] != "NVIM v0.12.6":
        raise RuntimeError("BLOCKED: installed stable no longer matches collection pin")
    print(json.dumps(dict(collection="2026-10-27", nvim=version,
                          hashes={name: hashlib.sha256(Path(name).read_bytes()).hexdigest()
                                  for name in ("/usr/bin/nvim", "/usr/bin/tmux", "/usr/bin/cc",
                                               "/usr/lib/libc.so.6", "/usr/lib/ld-linux-x86-64.so.2")})), flush=True)
    exe = root / "socket-fixture"
    fd_exe = root / "fd-fixture"
    loader = root / "loader-fixture.so"
    for source, output, extra in (("socket_fixture.c", exe, []), ("fd_fixture.c", fd_exe, []),
                                  ("loader_fixture.c", loader, ["-shared", "-fPIC"])):
        p = call(["/usr/bin/cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2", *extra,
                  str(HERE / source), "-o", str(output)], env)
        if p.returncode:
            raise RuntimeError("C fixture compile failed: " + p.stderr.decode()[:2000])
    check("BUILD-C11-system-libc-only", True, True)
    flags = call([str(fd_exe), "constants"], env).stdout.decode().strip()
    print(json.dumps(dict(header_derived_open_flags=int(flags),
                          probe_source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                               for p in sorted(HERE.iterdir()) if p.suffix in (".c", ".lua", ".py")})), flush=True)
    native_env = dict(env, PROBE_ROOT=str(root), PROBE_FIXTURE=str(fd_exe), PROBE_OPEN_FLAGS=flags,
                      PROBE_LOADER_LIBRARY=str(loader))
    p = call(["/usr/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "--noplugin", "-n",
              "-l", str(HERE / "capture.lua")], native_env)
    if p.returncode:
        raise RuntimeError("native capture probe failed: " + p.stderr.decode()[:1000])
    RESULTS.extend(json.loads((root / "capture.json").read_text()))

    def parse(case, payload, valid):
        p = call([str(exe), "parse"], env, input=payload)
        check(case, (p.returncode, p.stdout.decode().strip()), (0, "VALID") if valid else (3, "REJECTED"))

    basic = frame(root / "invoke", [str(exe)])
    fragmented = subprocess.Popen([str(exe), "parse"], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for byte in basic:
            fragmented.stdin.write(bytes([byte])); fragmented.stdin.flush()
            time.sleep(.001)
        fragmented.stdin.close()
        answer = fragmented.stdout.read()
        fragmented.wait(timeout=7)
        check("FRAME-one-byte-partial-I-O", (fragmented.returncode, answer.decode()), (0, "VALID\n"))
    finally:
        if fragmented.poll() is None:
            fragmented.terminate(); fragmented.wait(timeout=7)
    parse("FRAME-literal-empty-newline-nonUTF8", frame(root, [str(exe), b"", b";", b"\n", b"\xff"], [b"BYTE=\xff", b"EMPTY="]), True)
    for mode in (0, 1, 2):
        parse("FRAME-explicit-mode-" + str(mode), frame(root, ["/bin/sh", "-c", ""], mode=mode), True)
    parse("FRAME-8MiB-exact", frame(root, [str(exe), b"x" * (CAP - len(frame(root, [str(exe), b""])))]), True)
    too_big = bytearray(basic); too_big[4:8] = struct.pack("!I", CAP + 1)
    parse("FRAME-over-8MiB-header", bytes(too_big), False)
    parse("FRAME-65536-combined-entries", frame(root, [str(exe)] + [b""] * 65534, [b"X="]), True)
    parse("FRAME-65537-combined-rejected", frame(root, [str(exe)] + [b""] * 65535, [b"X="]), False)
    parse("FRAME-65536-combined-env-heavy", frame(root, [str(exe)], [b"K" + str(i).encode() + b"=" for i in range(65535)]), True)
    for case, payload in (
        ("truncated", basic[:-1]), ("trailing", basic + b"x"),
        ("version", b"SF02" + basic[4:]),
        ("NUL-argv", frame(root, [str(exe), b"a\0b"])),
        ("env-empty-name", frame(root, [str(exe)], [b"=x"])),
        ("env-missing-equals", frame(root, [str(exe)], [b"X"])),
        ("env-NUL", frame(root, [str(exe)], [b"X=\0"])),
        ("env-duplicate", frame(root, [str(exe)], [b"X=1", b"X=2"])),
        ("env-reserved-TMUX", frame(root, [str(exe)], [b"TMUX=x"])),
        ("env-reserved-pane", frame(root, [str(exe)], [b"TMUX_PANE=x"])),
        ("empty-argv", frame(root, [])),
        ("unresolved-executable", frame(root, ["pick"])),
    ):
        parse("FRAME-reject-" + case, payload, False)
    snapshot = {b"PROBE_SECRET": b"synthetic-request-only", b"PROBE_DROP": b"captured",
                b"PROBE_EMPTY": b"was-nonempty", b"PWD": b"captured-not-cwd",
                b"NVIM": b"synthetic-stale-address", b"TMUX": b"outer", b"TMUX_PANE": b"%999",
                b"TERM": b"outer-term", b"PATH": b"/deliberately/not/editor/path"}
    final, term_flag = environment(snapshot, {b"PROBE_DROP": False, b"PROBE_EMPTY": b""})
    check("ENV-fixture-false-unset-empty-and-inherit", b"PROBE_DROP=captured" not in final and b"PROBE_EMPTY=" in final and
          b"PWD=captured-not-cwd" in final and b"NVIM=synthetic-stale-address" in final and
          not any(s.startswith((b"TMUX=", b"TMUX_PANE=", b"TERM=")) for s in final) and term_flag == 1, True)
    for key in (b"TMUX", b"TMUX_PANE"):
        for value in (False, b"", b"override"):
            try:
                environment(snapshot, {key: value})
                rejected = False
            except ValueError:
                rejected = True
            check("ENV-reserved-" + key.decode() + "-" + ("false" if value is False else "empty" if not value else "string"), rejected, True)
    for key, value in ((b"", b"x"), (b"A=B", b"x"), (b"N\0", b"x"), (b"X", True), (b"X", 1), (b"X", b"\0")):
        try:
            environment(snapshot, {key: value})
            rejected = False
        except ValueError:
            rejected = True
        check("ENV-invalid-name-or-value-" + str(len(RESULTS)), rejected, True)
    for key in (b"TERM", b"PWD", b"NVIM"):
        for value in (False, b"", b"explicit"):
            values, default = environment(snapshot, {key: value})
            got = next((s[len(key) + 1:] for s in values if s.startswith(key + b"=")), None)
            check("ENV-policy-" + key.decode() + "-" + ("unset" if value is False else "empty" if not value else "override"),
                  got == (None if value is False else value) and (key != b"TERM" or default == 0), True)

    config = root / "tmux.conf"
    config.write_text("set -g default-shell /bin/sh\nset -g default-terminal tmux-256color\n"
                      "set -g update-environment ''\nset -s exit-empty off\nset -g remain-on-exit on\n")
    socket = root / "tmux.sock"
    safe_server = dict(env, PROBE_STALE="synthetic-safe-old-server")

    def tmux(*args, startup=False):
        return call(["/usr/bin/tmux", "-S", str(socket), "-f", str(config), *([] if startup else ["-N"]), *map(str, args)],
                    safe_server if startup else env)

    start = tmux("new-session", "-d", "-s", "probe", "/bin/sleep", "120", startup=True)
    if start.returncode:
        raise RuntimeError("private tmux start failed")
    marked = tmux("set-environment", "-t", "probe", "PROBE_SESSION", "synthetic-session-marker")
    if marked.returncode:
        tmux("kill-server")
        raise RuntimeError("private session marker setup failed")
    owned = []
    counter = 0
    try:
        handoff_env = dict(native_env, PROBE_SOCKET_FIXTURE=str(exe), PROBE_TMUX_SOCKET=str(socket))
        p = call(["/usr/bin/nvim", "--headless", "-u", "NONE", "-i", "NONE", "--noplugin", "-n",
                  "-l", str(HERE / "handoff.lua")], handoff_env)
        if p.returncode:
            raise RuntimeError("native socket handoff failed: " + p.stderr.decode()[:1000])
        RESULTS.extend(json.loads((root / "handoff.json").read_text()))
        # Positive loader control: the library acts BEFORE launcher main rejects it.
        mark = root / "unsafe-loader.mark"
        p = tmux("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "probe:",
                 "-e", "LD_PRELOAD=" + str(loader), "-e", "PROBE_LOADER_MARK=" + str(mark),
                 str(exe), "launcher", str(root / "absent.sock"), "1", str(OP))
        end = time.monotonic() + 3
        while time.monotonic() < end:
            if mark.exists() and mark.read_text() == "BOOTSTRAP\n":
                break
            time.sleep(.005)
        check("BOOTSTRAP-positive-LD_PRELOAD-before-main", p.returncode == 0 and mark.exists() and mark.read_text() == "BOOTSTRAP\n", True)

        # Adversarial ancillary senders are harness-only; receiver is the C launcher.
        for kind, count in (("missing", 0), ("regular-file", 1), ("two-directories", 2), ("control-truncation", 20),
                            ("truncated-frame", 1), ("trailing-frame", 1), ("wrong-frame-operation", 1)):
            directory = root / ("ancillary-" + kind); directory.mkdir(mode=0o700)
            path = directory / "s"
            with unix_socket.socket(unix_socket.AF_UNIX, unix_socket.SOCK_STREAM) as listener:
                listener.bind(str(path)); path.chmod(0o600); listener.listen(1); listener.settimeout(5)
                source = os.open(config if kind == "regular-file" else root / "invoke", os.O_RDONLY | os.O_CLOEXEC)
                try:
                    p = tmux("new-window", "-d", "-t", "probe:", str(exe), "launcher", str(path), str(os.getpid()), str(OP))
                    connection, _ = listener.accept()
                    with connection:
                        connection.settimeout(5)
                        hello = connection.recv(4)
                        ancillary = [] if not count else [(unix_socket.SOL_SOCKET, unix_socket.SCM_RIGHTS, array.array("i", [source] * count))]
                        connection.sendmsg([b"D"], ancillary)
                        if kind.endswith("frame") or kind == "wrong-frame-operation":
                            malformed = basic[:-1] if kind == "truncated-frame" else basic + b"x" if kind == "trailing-frame" else frame(root, ["/bin/true"], op=OP + 1)
                            connection.sendall(malformed)
                            connection.shutdown(unix_socket.SHUT_WR)
                        reply = b""
                        while len(reply) < 12:
                            data = connection.recv(12 - len(reply))
                            if not data:
                                break
                            reply += data
                        check(("TRANSPORT-reject-" if "frame" in kind else "FD-reject-") + kind, p.returncode == 0 and hello == struct.pack("!I", OP) and
                              reply == struct.pack("!3I", OP, 2, errno.EPROTO), True)
                finally:
                    os.close(source)
        for kind in ("existing-file", "symlink", "nonprivate-parent", "overlength"):
            directory = root / ("endpoint-" + kind); directory.mkdir(mode=0o700)
            path = directory / "s"
            if kind == "existing-file":
                path.write_text("owned-sentinel")
            elif kind == "symlink":
                path.symlink_to(root / "invoke")
            elif kind == "nonprivate-parent":
                directory.chmod(0o755)
            else:
                path = directory / ("x" * 108)
            source = os.open(root / "invoke", os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
            try:
                p = call([str(exe), "broker", str(path), str(source)], env, pass_fds=(source,), input=basic)
                check("ENDPOINT-refuse-" + kind, (p.returncode, p.stdout.decode().strip()), (3, "REJECTED"))
                if kind == "existing-file":
                    check("ENDPOINT-existing-data-not-deleted", path.read_text(), "owned-sentinel")
                if kind == "symlink":
                    check("ENDPOINT-ambiguous-link-not-deleted", path.is_symlink(), True)
            finally:
                os.close(source); directory.chmod(0o700)

        def launch(case, argv=None, extra_env=(), cwd=None, flags=1, mutate=None, expected="ACCEPTED_EXEC_UNVERIFIED", peer_delta=0, op_delta=0):
            nonlocal counter
            counter += 1
            directory = root / ("case" + str(counter)); directory.mkdir(mode=0o700)
            requested = cwd or root / "invoke"
            fd = os.open(requested, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC)
            endpoint = directory / "s"
            packet = frame(requested, argv or ["/bin/true"], extra_env, flags=flags)
            broker = subprocess.Popen([str(exe), "broker", str(endpoint), str(fd)], env=env,
                                      pass_fds=(fd,), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            owned.append(broker)
            os.close(fd)
            broker.stdin.write(packet); broker.stdin.close()
            if line(broker) != "BOUND":
                raise RuntimeError("C broker failed to bind")
            if mutate:
                mutate()
            p = tmux("new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "probe:", "--",
                     str(exe), "launcher", str(endpoint), str(broker.pid + peer_delta), str(OP + op_delta))
            pane = p.stdout.decode().strip()
            outcome = line(broker)
            broker.wait(timeout=7)
            check(case, outcome, expected)
            # Deliberately not an exec oracle, even when tmux returns zero.
            check(case + "-tmux-request-transport-only", p.returncode == 0 and pane.startswith("%") and pane[1:].isdigit(), True)
            if mutate:
                return
            inspection = tmux("display-message", "-p", "-t", pane, "#{pane_start_command}")
            text = inspection.stdout
            check(case + "-bootstrap-positive-inspection", inspection.returncode == 0 and b"launcher" in text and
                  os.fsencode(endpoint) in text and b"synthetic-request-only" not in text, True)
            return pane

        out = root / "workload.json"
        mark = root / "safe-loader.mark"
        actual_env = final + [b"LD_PRELOAD=" + os.fsencode(loader), b"PROBE_LOADER_MARK=" + os.fsencode(mark)]
        literals = [str(exe), "workload", str(out), b"", b";", b"#{pane_id}", b"#(false)", b"line\nnext", b"quote'\\\"$", b"\xff"]
        pane = launch("SOCKET-literal-env-FD-PTY-handoff", literals, actual_env)
        end = time.monotonic() + 3
        workload_ready = False
        while time.monotonic() < end:
            try:
                workload_ready = json.loads(out.read_text()) == {"ready": True}
                if workload_ready:
                    break
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(.005)
        check("SOCKET-workload-positively-ran", workload_ready, True)
        if workload_ready:
            sent = tmux("send-keys", "-t", pane, "-l", "synthetic-input")
            enter = tmux("send-keys", "-t", pane, "Enter")
            end = time.monotonic() + 3
            observed = None
            while time.monotonic() < end:
                try:
                    observed = json.loads(out.read_text())
                    if "input" in observed:
                        break
                except json.JSONDecodeError:
                    pass  # A result-file publication is not a synchronization barrier.
                time.sleep(.005)
            check("SOCKET-literal-env-PTY-input-CLOEXEC", observed if sent.returncode == enter.returncode == 0 else None,
                  dict(literal=True, environment=True, pty=True, no_extra_fds=True, term_default=True, input=True))
        check("BOOTSTRAP-safe-no-loader-before-main-workload-loader-allowed", mark.exists() and mark.read_text() == "WORKLOAD\n", True)
        for args in (("show-environment", "-g"), ("show-environment", "-t", "probe")):
            p = tmux(*args)
            marker = b"PROBE_STALE=synthetic-safe-old-server" if "-g" in args else b"PROBE_SESSION=synthetic-session-marker"
            check("SECRET-tmux-" + ("global" if "-g" in args else "session") + "-positive-inspection",
                  p.returncode == 0 and marker in p.stdout and
                  b"synthetic-request-only" not in p.stdout and os.fsencode(loader) not in p.stdout, True)
        check("SECRET-no-tmux-debug-logs-configured", not list(root.glob("tmux-*.log")), True)
        # Native-tested selection carried through absolute path despite child PATH/cwd.
        fallback = root / "fallback.result"
        script = root / "invoke/bin/fallback"
        script.write_text("test \"$1\" = 'literal;#{pane_id}' && printf OK > \"$2\"\n")
        script.chmod(0o700)
        launch("EXEC-glibc-ENOEXEC-literal-fallback", [str(script), "literal;#{pane_id}", str(fallback)], [b"PATH=/not/the/editor/path"], cwd=root / "placed")
        end = time.monotonic() + 3
        while time.monotonic() < end:
            if fallback.exists() and fallback.read_text() == "OK":
                break
            time.sleep(.005)
        check("EXEC-glibc-ENOEXEC-workload-positive-marker", fallback.exists() and fallback.read_text() == "OK", True)
        launch("EXEC-missing-attributable-error", [str(root / "missing")], expected="ERROR " + str(errno.ENOENT))
        launch("EXEC-kernel-E2BIG-below-product-cap", ["/bin/true", b"x" * 131073], expected="ERROR " + str(errno.E2BIG))
        largest = CAP - len(frame(root / "invoke", ["/bin/true", b""]))
        launch("SOCKET-8MiB-framed-request-kernel-E2BIG", ["/bin/true", b"x" * largest], expected="ERROR " + str(errno.E2BIG))
        denied = root / "not-executable"; denied.write_text("exit 0\n"); denied.chmod(0o600)
        launch("EXEC-EACCES-attributable-error", [str(denied)], expected="ERROR " + str(errno.EACCES))
        launch("STARTUP-EOF-without-complete-exchange-unknown", flags=3, expected="UNKNOWN")
        before = time.monotonic()
        launch("STARTUP-five-second-stalled-handshake-unknown", flags=5, expected="UNKNOWN")
        check("STARTUP-finite-five-second-deadline", 4.5 <= time.monotonic() - before < 7, True)
        launch("STARTUP-wrong-operation-ack-unknown", flags=9, expected="UNKNOWN")
        launch("PEER-wrong-broker-pid-unknown", peer_delta=100000, expected="UNKNOWN")
        launch("PEER-wrong-operation-request-unknown", op_delta=1, expected="UNKNOWN")
        for iteration in range(3):
            for change in ("rename", "replacement", "no-access"):
                original = root / (change + str(iteration)); original.mkdir(mode=0o700)
                moved = root / (change + str(iteration) + "-old")
                def mutate():
                    if change == "no-access":
                        original.chmod(0)
                    else:
                        original.rename(moved)
                        if change == "replacement":
                            original.mkdir(mode=0o700)
                try:
                    launch("CWD-final-" + change + "-" + str(iteration), cwd=original, mutate=mutate,
                           expected="ERROR " + str(errno.ESTALE))
                finally:
                    if original.exists():
                        original.chmod(0o700)
        link = root / "symlink"; link.symlink_to(root / "invoke", target_is_directory=True)
        launch("CWD-ordinary-symlink-to-pinned-object-allowed", cwd=link)
        execute_only = root / "execute-only"; execute_only.mkdir(mode=0o100)
        try:
            launch("CWD-O_PATH-execute-only-directory", cwd=execute_only)
        finally:
            execute_only.chmod(0o700)
    finally:
        for process in owned:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=7)
        stop = tmux("kill-server")  # Only this self-created explicit endpoint.
        check("CLEANUP-owned-private-server", stop.returncode, 0)
    for result in RESULTS:
        print(json.dumps(result, ensure_ascii=True), flush=True)
    failed = sum(result["status"] != "pass" for result in RESULTS)
    print(json.dumps(dict(summary=dict(passed=len(RESULTS) - failed, failed=failed),
                          qualification="partial-only; all I/R and remaining gates OPEN")), flush=True)
    return int(bool(failed))


if __name__ == "__main__":
    # Explicit /tmp, short pathname endpoints, private owned 0700 namespace.
    with tempfile.TemporaryDirectory(prefix="snf-", dir="/tmp") as directory:
        raise SystemExit(main(Path(directory)))
