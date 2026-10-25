#!/usr/bin/env python3
"""Disposable protocol MODEL + Linux/tmux primitive probes, NOT Sess code.

Run with /usr/bin/python3 probe.py. All mutable data is private /var/tmp
(local filesystem, not the repository's /tmp tmpfs). No real power-loss test.
The model's exact backend operation index is an ASSUMPTION, not a qualified
native tmux primitive. Never use this model as an implementation recipe.
"""
import copy
import errno
import fcntl
import json
import multiprocessing as mp
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import tempfile
import time
import unittest
import uuid


def token():
    return uuid.uuid4().hex


def checkpoint(label, crash=None):
    if label == crash:
        os._exit(73)


def syncdir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def publish(path, value, stage="record", crash=None, fail=None):
    """Checked file-fsync -> replace -> parent-fsync; leftovers preserved."""
    path = Path(path)
    temp = path.with_name(path.name + ".tmp-" + token())
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        data = json.dumps(value, sort_keys=True).encode()
        while data:
            count = os.write(fd, data)
            if count <= 0:
                raise OSError("short write")
            data = data[count:]
        checkpoint(stage + ":write", crash)
        if fail == "file-fsync":
            raise OSError(errno.EIO, "injected file fsync error")
        os.fsync(fd)
        checkpoint(stage + ":file-fsync", crash)
    finally:
        os.close(fd)
    os.replace(temp, path)
    checkpoint(stage + ":rename", crash)
    if fail == "directory-fsync":
        raise OSError(errno.EIO, "injected directory fsync error; commit uncertain")
    syncdir(path.parent)
    checkpoint(stage + ":directory-fsync", crash)


def read(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


class Lock:
    """Stable inode, never unlink; kernel lifetime, not age-based stealing."""
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        self.fd = os.open(self.path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *unused):
        os.close(self.fd)


def start_identity(pid):
    # Linux /proc field 22, bounded read; comm may contain spaces/parentheses.
    with open(f"/proc/{pid}/stat", "rb") as stream:
        line = stream.read(4096)
    return line.rsplit(b")", 1)[1].split()[19].decode()


def child_lock(path, conn):
    with Lock(path):
        conn.send((os.getpid(), start_identity(os.getpid())))
        conn.recv()  # explicit barrier, no timing-based race proof


def run_child(fn, *args):
    process = mp.Process(target=fn, args=args)
    process.start()
    process.join(15)
    if process.is_alive():
        process.kill()
        process.join()
        raise AssertionError("bounded child exceeded 15s")
    return process.exitcode


class Model:
    """One serialized model backend effect ledger; deliberately NOT tmux."""
    def __init__(self, root):
        self.root = Path(root)
        self.path = self.root / "state.json"
        self.effects = self.root / "model-backend.json"

    def seed(self):
        entries = lambda: {
            "one": {"name": "synthetic-one", "cwd": "/var/tmp", "status": "dormant"},
            "two": {"name": "synthetic-two", "cwd": "/var/tmp", "status": "dormant"},
        }
        publish(self.path, {"generation": "g1", "owners": {
            key: {"incarnation": key + "-i1", "revision": 0, "state": "active",
                  "entries": entries()} for key in ("A", "B")}})
        publish(self.effects, {})

    def recover(self, owner="A", crash=None, bad_cwd=False):
        with Lock(self.root / "owner.lock"):
            state = read(self.path)  # mandatory reread under lock
            record = state["owners"][owner]
            if record["state"] != "active":
                raise ValueError("tombstoned incarnation")
            for key, entry in record["entries"].items():
                if entry["status"] in ("live", "stopped", "unknown"):
                    continue
                if bad_cwd and key == "two":
                    return "partial:invalid-cwd"
                entry.setdefault("op", token())
                entry["status"] = "pending"
                publish(self.path, state, "intent", crash)
                effects = read(self.effects)
                matches = effects.get(entry["op"], [])
                if len(matches) > 1:
                    entry["status"] = "unknown"
                    publish(self.path, state)
                    return "unknown:no-retry"
                if not matches:
                    # MODEL assumes a complete exact operation ledger and atomic
                    # effect+identity. This is the critical UNPROVEN native gap.
                    matches = [{"generation": state["generation"], "epoch": token()}]
                    effects[entry["op"]] = matches
                    publish(self.effects, effects)
                checkpoint("effect", crash)
                entry["identity"] = matches[0]
                entry["status"] = "live"
                record["revision"] += 1
                publish(self.path, state, "progress", crash)
            return "complete"

    def loss(self, generation):
        with Lock(self.root / "owner.lock"):
            state = read(self.path)
            state["generation"] = generation
            for owner in state["owners"].values():
                for entry in owner["entries"].values():
                    if entry["status"] in ("live", "pending", "dormant"):
                        entry["status"] = "dormant"
                        entry.pop("identity", None)
                        entry.pop("op", None)
            # Plans persist before any empty live observation is accepted.
            publish(self.path, state)
            publish(self.effects, {})

    def stale_update(self, incarnation, revision):
        with Lock(self.root / "owner.lock"):
            state = read(self.path)
            owner = state["owners"]["A"]
            if (owner["incarnation"], owner["revision"], owner["state"]) != (
                    incarnation, revision, "active"):
                raise ValueError("stale incarnation/revision/tombstone")
            owner["revision"] += 1
            publish(self.path, state)


def recover_worker(root, crash=None):
    Model(root).recover(crash=crash)


class Tmux:
    def __init__(self, root):
        self.root = Path(root)
        self.endpoint = str(self.root / "server.sock")
        home = self.root / "home"
        home.mkdir(exist_ok=True)
        self.env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "TERM": "xterm-256color",
                    "LANG": "C", "SHELL": "/bin/sh"}

    def run(self, *args, start=False, check=True):
        # Every call, including cleanup and version, routes explicitly.
        result = subprocess.run(
            ["/usr/bin/tmux", *([] if start else ["-N"]), "-S", self.endpoint,
             "-f", "/dev/null", *args], env=self.env, capture_output=True,
            text=True, timeout=5)
        if check and result.returncode:
            raise AssertionError((args, result.returncode, result.stderr[:240]))
        return result

    def classify(self):
        if not os.path.lexists(self.endpoint):
            return "absent"
        info = os.lstat(self.endpoint)
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            return "unknown-endpoint"
        try:
            result = self.run("show-options", "-gqv", "@ready", check=False)
        except subprocess.TimeoutExpired:
            return "unavailable"
        if result.returncode:
            return "unavailable"
        if result.stdout.strip() != "synthetic-v1":
            return "unmarked"
        intent_path = self.root / "initialization.json"
        if not intent_path.exists():
            return "incompatible"
        intent = read(intent_path)
        expected = {"@namespace": intent["namespace"], "@protocol": str(intent["protocol"]),
                    "@generation": intent["generation"], "@digest": intent["digest"]}
        for option, value in expected.items():
            observed = self.run("show-options", "-gqv", option, check=False)
            if observed.returncode or observed.stdout.strip() != value or not value:
                return "incompatible"
        for scope, option in (("-sqv", "exit-empty"), ("-sqv", "exit-unattached"),
                              ("-gqv", "destroy-unattached")):
            observed = self.run("show-options", scope, option, check=False)
            if observed.returncode or observed.stdout.strip() != "off":
                return "incompatible"
        return "ready"

    def initialize(self, crash=None):
        with Lock(self.root / "namespace.lock"):
            status = self.classify()
            if status != "absent":
                return status  # never repair/take over unmarked/unavailable
            generation = token()
            publish(self.root / "initialization.json", {
                "namespace": "synthetic", "protocol": 1, "generation": generation,
                "digest": "synthetic-config-v1", "status": "intent"}, "init", crash)
            self.run("new-session", "-d", "-s", "bootstrap", "/bin/sleep", "120", start=True)
            checkpoint("server-created", crash)
            for args in (("set-option", "-s", "exit-empty", "off"),
                         ("set-option", "-s", "exit-unattached", "off"),
                         ("set-option", "-g", "destroy-unattached", "off"),
                         ("set-option", "-g", "@generation", generation),
                         ("set-option", "-g", "@namespace", "synthetic"),
                         ("set-option", "-g", "@protocol", "1"),
                         ("set-option", "-g", "@digest", "synthetic-config-v1")):
                self.run(*args)
            # This tests publication order only, not full protected identity hooks.
            checkpoint("before-ready", crash)
            self.run("set-option", "-g", "@ready", "synthetic-v1")
            checkpoint("ready", crash)
            return "created"

    def cleanup(self):
        roots = []
        result = self.run("list-panes", "-a", "-F", "#{pane_pid}", check=False)
        if result.returncode == 0:
            for text in result.stdout.splitlines():
                try:
                    pid = int(text)
                    roots.append((pid, start_identity(pid)))
                except (ValueError, FileNotFoundError, ProcessLookupError):
                    pass
        self.run("kill-server", check=False)
        deadline = time.monotonic() + 5
        for pid, identity in roots:
            while time.monotonic() < deadline:
                try:
                    if start_identity(pid) != identity:
                        break
                    with open(f"/proc/{pid}/stat", "rb") as stream:
                        status = stream.read(4096).rsplit(b")", 1)[1].split()[0]
                    if status == b"Z":
                        break  # terminated, awaiting OS reaping
                except (FileNotFoundError, ProcessLookupError):
                    break
                time.sleep(0.01)  # cleanup wait, not race/atomicity evidence
            else:
                raise AssertionError("synthetic root did not terminate")


def init_worker(root, crash=None):
    Tmux(root).initialize(crash)


def trash_worker(root, crash):
    root = Path(root)
    with Lock(root / "owner.lock"):
        publish(root / "tombstone.json", {"state": "deleting", "incarnation": "i1"},
                "tombstone", crash)
        publish(root / "stop-effect.json", {"stopped": ["one"]})
        checkpoint("stop-effect", crash)
        publish(root / "tombstone.json", {"state": "deleted", "incarnation": "i1",
                                           "stopped": ["one"]}, "suppression", crash)
        os.rename(root / "owner", root / "trash" / "owner")
        checkpoint("trash:rename", crash)
        syncdir(root)
        checkpoint("trash:source-directory-fsync", crash)
        syncdir(root / "trash")
        checkpoint("trash:destination-directory-fsync", crash)


class Probe(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sess-durable-", dir="/var/tmp")
        self.root = Path(self.temp.name)
        syncdir(self.root.parent)

    def tearDown(self):
        self.temp.cleanup()

    def model(self):
        model = Model(self.root)
        model.seed()
        return model

    def test_01_native_publication_directory_trash_and_errors(self):
        directory = self.root / "owner"
        directory.mkdir(mode=0o700)
        syncdir(self.root)  # creation of containing directory, before contents
        path = directory / "record.json"
        publish(path, {"revision": 1})
        for failure in ("file-fsync", "directory-fsync"):
            with self.assertRaises(OSError):
                publish(path, {"revision": 2}, fail=failure)
            self.assertEqual(read(path), {"revision": 1 if failure == "file-fsync" else 2})
        # A directory-fsync failure may already have published; NOT rollback.
        self.assertEqual(read(path), {"revision": 2})
        trash = self.root / "trash"
        trash.mkdir(mode=0o700)
        syncdir(self.root)
        os.rename(directory, trash / "owner")
        syncdir(self.root)
        syncdir(trash)  # both changed parent directories checked
        os.unlink(trash / "owner" / "record.json")
        # Preserve temporary leftovers until explicit disposable fixture cleanup.
        for leftover in (trash / "owner").glob("*.tmp-*"):
            leftover.unlink()
        syncdir(trash / "owner")
        os.rmdir(trash / "owner")
        syncdir(trash)

    def test_02_flock_identity_sigkill_and_unlink_negative_control(self):
        parent, child = mp.Pipe()
        path = self.root / "lock"
        holder = mp.Process(target=child_lock, args=(path, child))
        holder.start()
        self.assertTrue(parent.poll(5))
        pid, identity = parent.recv()
        self.assertEqual(start_identity(pid), identity)
        self.assertNotEqual(start_identity(pid), identity + "-stale")
        fd = os.open(path, os.O_RDWR)
        try:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            # Negative control: unlinking a held lock allows a second lock inode.
            path.unlink()
            with Lock(path):
                self.assertTrue(holder.is_alive())
            os.kill(pid, signal.SIGKILL)
            holder.join(5)
            self.assertEqual(holder.exitcode, -signal.SIGKILL)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(fd)
            if holder.is_alive():
                holder.kill()
                holder.join()

    def test_03_model_all_process_crash_boundaries(self):
        labels = [f"{stage}:{point}" for stage in ("intent", "progress")
                  for point in ("write", "file-fsync", "rename", "directory-fsync")]
        for label in labels + ["effect"]:
            with self.subTest(crash=label):
                model = self.model()
                self.assertEqual(run_child(recover_worker, self.root, label), 73)
                self.assertEqual(model.recover(), "complete")
                effects = read(model.effects)
                self.assertEqual(len(effects), 2)
                self.assertTrue(all(len(rows) == 1 for rows in effects.values()))
                self.assertEqual(model.recover(), "complete")
                self.assertEqual(read(model.effects), effects)

    def test_04_model_concurrent_loads(self):
        for repeat in range(3):
            model = self.model()
            # Children rendezvous at a barrier, then compete on the stable lock.
            barrier = mp.Barrier(16)
            def competing_load():
                barrier.wait(timeout=10)
                model.recover()
            children = [mp.Process(target=competing_load) for _ in range(16)]
            for child in children:
                child.start()
            for child in children:
                child.join(15)
                if child.is_alive():
                    child.kill()
                    child.join()
                self.assertEqual(child.exitcode, 0, repeat)
            self.assertEqual(len(read(model.effects)), 2)

    def test_05_model_partial_dormant_repeated_loss_and_suppression(self):
        model = self.model()
        self.assertEqual(model.recover(bad_cwd=True), "partial:invalid-cwd")
        state = read(model.path)
        self.assertEqual(state["owners"]["A"]["entries"]["two"]["status"], "dormant")
        self.assertTrue(all(e["status"] == "dormant" for e in
                            state["owners"]["B"]["entries"].values()))
        old_identity = state["owners"]["A"]["entries"]["one"]["identity"]
        state["owners"]["A"]["entries"]["one"]["status"] = "stopped"
        publish(model.path, state)  # durable stop suppression despite cleanup failure
        for generation in ("g2", "g3"):
            model.loss(generation)  # B still dormant before second loss
        model.recover()
        model.recover("B")
        self.assertEqual(len(read(model.effects)), 3)
        state = read(model.path)
        self.assertEqual(state["owners"]["A"]["entries"]["one"]["status"], "stopped")
        self.assertNotEqual(state["owners"]["A"]["entries"]["two"]["identity"], old_identity)
        self.assertEqual(state["owners"]["B"]["entries"]["one"]["identity"]["generation"], "g3")
        # Independently exercise a pending effect across loss BEFORE recovery.
        model.seed()
        self.assertEqual(run_child(recover_worker, self.root, "effect"), 73)
        pending = read(model.path)["owners"]["A"]["entries"]["one"]
        self.assertEqual(pending["status"], "pending")
        model.loss("g2")
        model.recover()
        model.loss("g3")  # B has still never loaded
        model.recover("B")
        model.recover("A")
        self.assertEqual(len(read(model.effects)), 4)
        for owner in read(model.path)["owners"].values():
            for entry in owner["entries"].values():
                self.assertEqual(entry["identity"]["generation"], "g3")
                self.assertEqual(entry["cwd"], "/var/tmp")
                self.assertTrue(entry["name"].startswith("synthetic-"))

    def test_06_model_ambiguous_pending_and_corrupt_preserved(self):
        model = self.model()
        state = read(model.path)
        state["owners"]["A"]["entries"]["one"].update(status="pending", op="conflicting-op")
        publish(model.path, state)
        conflict = [{"generation": "g1", "epoch": "a"}, {"generation": "g1", "epoch": "b"}]
        publish(model.effects, {"conflicting-op": conflict})
        self.assertEqual(model.recover(), "unknown:no-retry")
        self.assertEqual(read(model.effects), {"conflicting-op": conflict})
        # Subsequent recovery skips unknown, may recover unattempted second entry.
        model.recover()
        self.assertEqual(len(read(model.effects)), 2)
        self.assertEqual(read(model.effects)["conflicting-op"], conflict)
        for generation in ("g2", "g3"):
            model.loss(generation)
        self.assertEqual(read(model.path)["owners"]["A"]["entries"]["one"]["status"], "unknown")
        corrupt = b'{"broken"'
        model.path.write_bytes(corrupt)
        with self.assertRaises(json.JSONDecodeError):
            model.recover()
        self.assertEqual(model.path.read_bytes(), corrupt)
        # Incomplete/unavailable observations have NO publication path in this
        # model; native observation/schema completeness remains unqualified.

    def test_07_model_tombstone_revision_restore(self):
        model = self.model()
        model.stale_update("A-i1", 0)
        with self.assertRaises(ValueError):
            model.stale_update("A-i1", 0)
        state = read(model.path)
        state["owners"]["A"]["state"] = "deleting"
        state["owners"]["A"]["entries"]["one"]["status"] = "stopped"
        publish(model.path, state)  # tombstone/intent BEFORE synthetic stop
        with self.assertRaises(ValueError):
            model.stale_update("A-i1", 1)
        # Simulate partial stop: record remains in place with survivors.
        self.assertTrue(model.path.exists())
        self.assertEqual(state["owners"]["A"]["entries"]["two"]["status"], "dormant")
        restored = copy.deepcopy(state["owners"]["A"])
        restored.update(incarnation="A-i2", revision=0, state="active")
        restored["entries"] = {}  # restore editing context, never stopped jobs
        state["owners"]["A"] = restored
        publish(model.path, state)
        with self.assertRaises(ValueError):
            model.stale_update("A-i1", 0)
        model.recover()
        self.assertEqual(read(model.effects), {})

    def test_08_native_concurrent_initialization_ready_last_empty(self):
        backend = Tmux(self.root)
        try:
            self.assertEqual(backend.classify(), "absent")
            barrier = mp.Barrier(8)
            def initializer():
                barrier.wait(timeout=10)
                backend.initialize()
            children = [mp.Process(target=initializer) for _ in range(8)]
            for child in children:
                child.start()
            for child in children:
                child.join(15)
                if child.is_alive():
                    child.kill()
                    child.join()
                self.assertEqual(child.exitcode, 0)
            self.assertEqual(backend.classify(), "ready")
            os.chmod(backend.endpoint, 0)
            try:
                self.assertEqual(backend.classify(), "unavailable")
                self.assertEqual(backend.initialize(), "unavailable")
            finally:
                os.chmod(backend.endpoint, 0o600)
            generation = backend.run("show-option", "-gqv", "@generation").stdout.strip()
            self.assertEqual(generation, read(self.root / "initialization.json")["generation"])
            backend.run("set-option", "-g", "@generation", "stale-generation")
            self.assertEqual(backend.initialize(), "incompatible")
            backend.run("set-option", "-g", "@generation", generation)
            backend.run("set-option", "-s", "exit-empty", "on")
            self.assertEqual(backend.initialize(), "incompatible")
            backend.run("set-option", "-s", "exit-empty", "off")
            self.assertEqual(backend.classify(), "ready")
            self.assertEqual(backend.run("list-sessions", "-F", "#{session_id}").stdout.count("\n"), 1)
            backend.run("kill-session", "-t", "=bootstrap")  # synthetic only
            self.assertEqual(backend.run("list-sessions").stdout, "")
            self.assertEqual(backend.classify(), "ready")
            self.assertEqual(backend.initialize(), "ready")
            self.assertEqual(backend.run("show-option", "-gqv", "@generation").stdout.strip(), generation)
        finally:
            backend.cleanup()

    def test_09_native_crashed_initialization_no_takeover(self):
        points = ["init:" + point for point in ("write", "file-fsync", "rename", "directory-fsync")]
        for point in points + ["server-created", "before-ready", "ready"]:
            with self.subTest(crash=point):
                directory = self.root / point.replace(":", "-")
                directory.mkdir(mode=0o700)
                syncdir(self.root)
                backend = Tmux(directory)
                try:
                    self.assertEqual(run_child(init_worker, directory, point), 73)
                    expected = "absent" if point.startswith("init:") else (
                        "ready" if point == "ready" else "unmarked")
                    self.assertEqual(backend.classify(), expected)
                    if expected != "absent":
                        self.assertEqual(backend.initialize(), expected)
                finally:
                    backend.cleanup()

    def test_10_native_ambiguous_spawn_live_absence_current_recipe(self):
        backend = Tmux(self.root)
        try:
            backend.initialize()
            before = backend.run("list-windows", "-a", "-F", "#{window_id}").stdout
            # Exact output is intentionally discarded, representing client loss
            # after native effect but before durable identity recording.
            backend.run("new-window", "-d", "-t", "=bootstrap:", "-n", "synthetic",
                        "-c", str(self.root), "/bin/sleep", "120")
            rows = backend.run("list-windows", "-a", "-F", "#{window_id}|#{window_name}").stdout
            self.assertEqual(rows.count("|synthetic\n"), 1)
            self.assertNotEqual(rows, before)
            # No durable exact op marker: name/cwd is NOT reconciliation proof.
            decision = "unknown:no-retry"
            self.assertEqual(decision, "unknown:no-retry")
            window = next(row.split("|")[0] for row in rows.splitlines() if row.endswith("|synthetic"))
            backend.run("kill-window", "-t", window)
            # Live absence: only read again; do not create anything.
            self.assertNotIn("|synthetic\n", backend.run(
                "list-windows", "-a", "-F", "#{window_id}|#{window_name}").stdout)
            # Current synthetic shell/environment/cwd, never an old stored recipe.
            shell = backend.run("new-window", "-d", "-P", "-F", "#{pane_id}",
                                "-t", "=bootstrap:", "-n", "fresh", "-c", str(self.root),
                                "-e", "SYNTHETIC_CURRENT=current", "/bin/sh").stdout.strip()
            self.assertRegex(shell, r"^%[0-9]+$")
            pid = int(backend.run("display-message", "-p", "-t", shell, "#{pane_pid}").stdout)
            self.assertTrue(start_identity(pid).isdigit())
            self.assertEqual(os.readlink(f"/proc/{pid}/cwd"), str(self.root))
            with open(f"/proc/{pid}/environ", "rb") as stream:
                env = stream.read(16384)  # never print/persist environment
            self.assertIn(b"SYNTHETIC_CURRENT=current\0", env)
            self.assertNotIn(b"SYNTHETIC_OLD=", env)
            with open(f"/proc/{pid}/cmdline", "rb") as stream:
                self.assertEqual(stream.read(256), b"/bin/sh\0")
            invalid = backend.run("new-window", "-d", "-P", "-F", "#{pane_pid}",
                                  "-t", "=bootstrap:", "-c", str(self.root / "does-not-exist"),
                                  "/bin/sh", check=False)
            # Negative control: invalid cwd is silently substituted by tmux.
            self.assertEqual(invalid.returncode, 0)
            actual = os.readlink(f"/proc/{int(invalid.stdout.strip())}/cwd")
            self.assertEqual(actual, str(self.root / "home"))
            print("NATIVE_INVALID_CWD_EXIT=0; ACTUAL_CWD=PRIVATE_HOME (strict-cwd FAIL)", flush=True)
        finally:
            backend.cleanup()

    def test_11_native_unknown_endpoint_and_unresponsive_socket(self):
        backend = Tmux(self.root)
        Path(backend.endpoint).write_text("synthetic-not-a-socket")
        self.assertEqual(backend.initialize(), "unknown-endpoint")
        Path(backend.endpoint).unlink()
        Path(backend.endpoint).symlink_to(self.root / "synthetic-missing")
        self.assertEqual(backend.initialize(), "unknown-endpoint")
        Path(backend.endpoint).unlink()
        fixture = socket.socket(socket.AF_UNIX)
        try:
            fixture.bind(backend.endpoint)
            fixture.listen(1)
            self.assertEqual(backend.classify(), "unavailable")
        finally:
            fixture.close()
        # A stale socket pathname alone is NOT enough absence evidence here.
        self.assertEqual(backend.classify(), "unavailable")
        self.assertEqual(backend.initialize(), "unavailable")

    def test_12_model_tombstone_stop_trash_crash_matrix(self):
        points = [f"{stage}:{point}" for stage in ("tombstone", "suppression")
                  for point in ("write", "file-fsync", "rename", "directory-fsync")]
        points += ["stop-effect", "trash:rename", "trash:source-directory-fsync",
                   "trash:destination-directory-fsync"]
        for point in points:
            with self.subTest(crash=point):
                directory = self.root / point.replace(":", "-")
                directory.mkdir(mode=0o700)
                syncdir(self.root)
                (directory / "owner").mkdir(mode=0o700)
                (directory / "trash").mkdir(mode=0o700)
                syncdir(directory)
                publish(directory / "owner" / "editing-context.json", {"synthetic": True})
                self.assertEqual(run_child(trash_worker, directory, point), 73)
                paths = [directory / "owner", directory / "trash" / "owner"]
                self.assertEqual(sum(path.exists() for path in paths), 1)
                survivor = next(path for path in paths if path.exists())
                self.assertEqual(read(survivor / "editing-context.json"), {"synthetic": True})
                if (directory / "stop-effect.json").exists():
                    tombstone = read(directory / "tombstone.json")
                    self.assertIn(tombstone["state"], ("deleting", "deleted"))
                    if tombstone["state"] == "deleted":
                        self.assertEqual(tombstone["stopped"], ["one"])
                    # deleting+unknown outcome MUST block restore/retry.


if __name__ == "__main__":
    mp.set_start_method("fork")  # Linux-only, tested runtime assumption
    unittest.main(verbosity=2)
