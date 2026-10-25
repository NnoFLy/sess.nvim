# tmux isolation, clients, and bounded observation qualification

## Result and authority

**Research evidence only; implementation handoff remains blocked.** On the pinned
Linux/tmux tuple, the final generic probe passed **32 checks in each of five runs
(160/160)**. The separate system/user/plugin configuration sentinel probe passed
**five of five runs**. These are scoped primitive results, not a full #34 gate pass,
Neovim compatibility, phone-app compatibility, or feature implementation approval.
Required untested/blocked cases are listed below rather than silently waived.

- Ticket: [#34](https://github.com/NnoFLy/sess.nvim/issues/34).
- Acceptance: [#32 resolution](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573).
- Controlling resolutions: [backend/config boundary #28](https://github.com/NnoFLy/sess.nvim/issues/28#issuecomment-6377864668),
  [live authority/identity/recovery #30](https://github.com/NnoFLy/sess.nvim/issues/30#issuecomment-6387360218),
  [external clients/agents #31](https://github.com/NnoFLy/sess.nvim/issues/31#issuecomment-6391314744).
- Lane: `backend-clients`; branch: `research/persistent-terminal-backend-clients`;
  base: `eee53cc`. The commit containing this document and its probes is the
  evidence revision (resolve with `git rev-parse HEAD`); the publication report
  supplies its immutable GitHub blob URL. No tracker mutation or PR is authorized.
- Collected: **2026-10-25 UTC**, final generic run completed at 00:40:47Z.

**Boundary:** #33 owns native identity/attachment/stop atomicity and epoch ordering;
#35 owns coordinated initialization/recovery/storage crash durability; #36 owns
stable-Neovim terminal semantics. This lane does not duplicate or pass those proofs.
The raw grouped-creation and cleanup commands in the disposable probes have no
production identity guard. They must not be copied as a safe attachment recipe.

## Exact runtime and assumptions

| Component | Observed provenance |
| --- | --- |
| Host | Linux `7.2.10-arch1-1`, `x86_64`, GNU/Linux; same host, no reboot during probes |
| tmux | `/usr/sbin/tmux` resolves to `/usr/bin/tmux`, `tmux 3.8`; Arch package `tmux 3.8-1`, package signature validated according to `pacman -Qi`; build date 2026-10-08 09:15:58 UTC |
| tmux executable SHA-256 | `f4d25f698c2eae25b742ad8a6d4cb8c7c5309a6ebf586e4e541fc9655de10660` |
| Shell | `/bin/sh`, GNU bash `5.3.20(1)-release`, Arch `bash 5.3.20-1`; SHA-256 `c14c8f498f3be96f076ceb07d65dba584a86dca3c86b5dce65ed0f6cae73358d` |
| Probe interpreter | Python `3.14.8`, Arch `python 3.14.8-1`; `/usr/bin/python3` SHA-256 `375532f83be620283ab780c14ca6bcc5907dc379d2b621de0c5d0a112cf5458b` |
| Official stable Neovim | GitHub `releases/latest`: **v0.12.6**, published 2026-10-09T15:43:25Z; annotated tag `022946c802832f938398dfae34b3f277ca9509d4` -> source `779c36969e31080503be2dfccbcc3f999e289606` |
| Installed Neovim (not qualified) | `NVIM v0.13.0-dev-d714648-dirty`, RelWithDebInfo, LuaJIT `2.1.1792527110`; executable SHA-256 `557198ff1a62ba5c1d5dc6682f230ba600c83971a17eb5b150e0a7e1b5bce93f`; **not substituted for stable** |
| Scratch/worktree | `/tmp`, `tmpfs`, `rw,nosuid,nodev,nr_inodes=1048576,inode64,huge=advise,usrquota`; all probe state/sockets under private `mkdtemp` directories, mode 0700, umask 077 |
| Executables | Root mount btrfs, `rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2`; no package installation or binary rebuild |
| PTYs/procfs | `/dev/pts`: devpts, `rw,nosuid,noexec,relatime,gid=5,mode=600,ptmxmode=000`; `/proc`: proc, `rw,nosuid,nodev,noexec,relatime`; Yama ptrace scope 1; same-UID fixture reads permitted |

No power-loss/durable-storage conclusion follows from tmpfs or these process-loss
checks. Arch package identity plus executable hash is exact runtime provenance;
this is not a claim of a reproducible binary-to-upstream-source build comparison.
User+mount namespaces (`unshare -Urnm`) are available; this is an optional prerequisite
for reproducing the system-config sentinel probe, not a proposed plugin dependency.

### Primary sources (D)

Official tmux tag `3.8` object `72c20dc22c24c34b8e39506f524c9c88da2f48aa`
resolves to **`7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`**. All tmux links below
pin that exact revision, fetched with `gh api .../contents/<file>?ref=<sha>`.

| Source | Relevant fact, not a runtime pass |
| --- | --- |
| [tmux.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.c#L423-L452), [cfg.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cfg.c#L87-L92) | First `-f` clears **all** compiled config entries, then loads only explicit files; not merely a user-config override. |
| [tmux.c socket routing](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.c#L556-L578) | Explicit `-S` precedes inherited `TMUX`; `-N` sets no-start-server behavior. |
| [manual](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1) | Startup config once; grouped presentations share membership, not current selection; `-E`; read-only/ignore-size; `capture-pane -S/-E` numbering. |
| [options-table.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/options-table.c), [server.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L285-L296) | `exit-empty` defaults on; controlled survival requires explicit observation of server/session/window settings. |
| [cmd-new-session.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-new-session.c#L315-L326), [session.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/session.c#L643-L675) | Group synchronization follows initial spawn; presentation creation can have transient default-command startup effects. |
| [resize.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/resize.c#L87-L135), [viewer filtering](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/resize.c#L344-L382) | Ignore-size is conditional on other clients; latest-client selection and aggressive current-viewer filtering are separate tests. A stale/non-viewer latest pointer can leave geometry unchanged until suitable activity. |
| [server-client.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server-client.c#L359-L390), [input activity](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server-client.c#L1690-L1712) | Lost-client selection chooses a remaining current viewer; input/read-only processing can update latest activity; output alone is not this path. |
| [spawn.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L76-L110), [hooks.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/hooks.c#L199-L249) | `pane-created` carries pane/window/session payload, including respawn flag. A working hook is only a capability, not verified epoch/atomicity handling. |
| [Linux proc documentation](https://github.com/torvalds/linux/blob/8d3ae59288f1e7d58d76558a6ee96d533bc5019f/Documentation/filesystems/proc.rst), [stat implementation](https://github.com/torvalds/linux/blob/8d3ae59288f1e7d58d76558a6ee96d533bc5019f/fs/proc/array.c#L584-L611) | Official `v7.2` source `8d3ae59288f1e7d58d76558a6ee96d533bc5019f`; start time comes from boot-time ticks, children files are task-scoped and explicitly not precise under concurrent exits. Running kernel has Arch patches; not asserted byte-identical. |
| [existing process probe](https://github.com/NnoFLy/sess.nvim/blob/eee53cca450a1e1a64e47ebe43f507fe85669dd0/lua/sess/agent/process_probe.lua) | Source seam only: existing known-agent names and conservative depth/process/argv bounds; no implementation changed or executed by this lane. |

The installed tmux binary's compiled search string is
`/etc/tmux.conf:~/.tmux.conf:$XDG_CONFIG_HOME/tmux/tmux.conf:~/.config/tmux/tmux.conf`.
All four locations receive synthetic sentinels in the namespace test.

## Reproduction, safety, and oracles (P)

Assets:

- [`probes/backend-clients/probe.py`](probes/backend-clients/probe.py): disposable
  command/shell roots, real PTYs, grouped sessions, observations, negative controls.
- [`probes/backend-clients/system_isolation.py`](probes/backend-clients/system_isolation.py):
  system/user/plugin sentinels in a private user+mount namespace; never writes host `/etc`.

Run from this evidence commit, with the already installed tools:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 docs/research/probes/backend-clients/probe.py
PYTHONDONTWRITEBYTECODE=1 python3 docs/research/probes/backend-clients/system_isolation.py
```

Expected exit: 0. Generic final line: `{"summary": {"pass": 32, "fail": 0}}`.
System probe prints one `system-user-plugin-config-isolation` row, `status: pass`.
The recorded final validation repeated each command five times. Generic runs all
reported 32/0; all five system rows passed. These are repeated scenario checks,
**not race stress/atomicity evidence**.

Every server command, including cleanup, uses `-S <absolute disposable socket>`;
non-starting commands use `-N`. No default server is queried. The only deliberately
conflicting `TMUX` variable names another freshly created disposable socket. A
private env whitelist sets PATH, HOME, XDG_CONFIG_HOME, TERM, LC_ALL, SHELL and
TMUX_TMPDIR; no inherited real credentials/environment are recorded. System test
uses synthetic NSS files, maps the invoking UID to namespace root, verifies a new
mount namespace, makes propagation private, then bind-mounts private synthetic
`/etc`. Namespace teardown removes that mount; host services/config remain intact.

Core controlled settings are `exit-empty off`, `exit-unattached off`,
`destroy-unattached off`, `remain-on-exit off`, `window-size latest`,
`aggressive-resize on`, `status off`, `/bin/sh`, and a synthetic `pane-created`
stamp. The Python workload has a synthetic known-agent child (`codex` symlink to
`/bin/sleep`), counters and a SIGINT handler. A separate actual `/bin/sh -i` root
also survives the zero-client sequence. The child ignores SIGINT so the shared
Ctrl-C oracle can be exercised without terminating the later observation fixture;
this is not a statement about real agents' signal behavior.

PTYs are ordinary forked controlling terminals, not tmux control mode or mocked
clients. Dimensions are 100x30 and 60x20; native resize also tests 70x22. PTY
screen bytes are discarded in bounded 64-KiB reads. No pane text is printed/stored.
Fixture counters live only in private temporary storage, deleted on exit.

Process reads start at the exact `pane_pid` and Linux stat field-22 identity, not
client PID/name/command history. Stat and children reads cap at 4096 bytes; argv
at 32768; traversal at depth 8, 256 visited processes and 256 children/task.
Fixture-only capture is `capture-pane -p -t %EXACT -S 0 -E 5` (six **visible**
lines, not `-S -5`, which includes history), width at most 100 here. Command output
has an 8192-byte post-capture assertion and a 5-second timeout. This is not a
production streaming memory cap for arbitrary Unicode/width/untrusted servers;
no arbitrary pane output is collected. Captured text is transient, association is
rechecked, and only synthetic marker presence/length/count is published.

## Observed matrix

Each **pass** below means the stated narrow oracle passed in all five final runs.
Checks are predicate-polled (3-second deadline), not a fixed sleep substituted for
an oracle. Brief 0.15–0.2-second settle/observation intervals cannot prove indefinite
lifetime or absence of all races.

| Case IDs (exact probe keys) | Status | Expected -> observed |
| --- | --- | --- |
| `private-endpoint` | pass | Own private directory 0700, own socket type/UID -> socket 0600, 32-byte pathname, same UID. |
| `user-plugin-config-isolation`, `config-sentinel-positive-control` | pass | Explicit `-f` skips private user/plugin sentinels; explicit sentinel file must trigger them -> both oracles held. |
| `system-user-plugin-config-isolation` (separate probe) | pass | Default startup sees synthetic `/etc` and user sentinel/plugin; controlled `-f` sees none -> all booleans true, five runs. Complete tmux config-search isolation for this binary; not arbitrary same-UID attacker isolation. |
| `protected-options` | pass | Observe off/off/off/latest/on/off -> exact matches for exit-empty/exit-unattached/destroy-unattached/window-size/aggressive-resize/remain-on-exit. |
| `native-create-hook-capability` | pass | Native single-pane new-window gets hook stamp with no creation helper -> `@probe-created=yes`. No admission/identity/epoch-ordering claim. |
| `group-presentation-no-extra-window` | pass | Two grouped presentations share four existing windows, leave no extra root -> four canonical windows/four server direct children; **two** accepted transient shell startup writes per run. This is a live post-creation check, not an arbitrary-hook orphan-process proof. |
| `attach-latest-sizing`, `pty-resize-event` | pass | Latest second attach supplies 60x20; resize -> 70x22 -> 60x20. |
| `two-pty-shared-input-control` | pass | Writable clients append `a`, `b` to one root and deliver Ctrl-C -> `ab`, one SIGINT, same root PID/start. |
| `latest-keyboard-sizing` | pass | First client's key -> 100x30; second client's key -> 60x20. Geometry is shared, not independent. |
| `output-only-no-latest-change` | pass | SIGUSR1 causes pane output without client input -> stays 60x20. |
| `independent-navigation-nonviewer` | pass | Presentations select distinct exact windows; non-viewer's activity does not size first window -> selection stays independent; first window 100x30 after its suitable viewer's activity. |
| `normal-abrupt-loss-zero-clients` | pass | SIGKILL latest client, native-detach remaining client -> remaining viewer 100x30; zero clients; same command **and interactive shell** PID/start identities. |
| `reattach-identical-workload` | pass | New PTY attaches surviving presentation -> same command and shell identities, no replay. |
| `readonly-ignore-size` | pass | `-r` blocks fixture writes and ignores size alongside writable client -> no `j`/`k` input, 100x30 with writable; **40x12 with only read-only client**. Thus ignore-size is not an unconditional size lock. |
| `native-rename-duplicate-labels` | pass | Native rename two exact windows to same label -> both rows visible with distinct IDs, unchanged process identity. No name-uniqueness adapter implemented. |
| `unsupported-multipane-visible-preserved` | pass | Native split produces unsupported shape -> two panes visible, preserved until scratch-server teardown. No adoption or safe-mutation qualification. |
| `presentation-only-cleanup` | pass | Remove one detached scratch presentation -> canonical exact windows/root and other presentation unchanged. Sequential, no hostile concurrent relink/anchor-loss guard. |
| `natural-signaled-exit` | pass | Native typed `q` ends one root, SIGTERM ends second synthetic root -> both exact panes disappear, both root process identities end; old process observation unknown; no replay. Split window's separate pane is not swept into this signal. |
| `empty-server-survival` | pass | Remove final known scratch windows -> no sessions/windows, same server PID/start identity and generation retained. |
| `empty-server-negative-control` | pass | `/dev/null` configuration leaves default exit-empty -> separate disposable server disappears on final-session removal. Oracle distinguishes normal emptiness from default shutdown. |
| `explicit-routing-unrelated-protected` | pass | Conflicting TMUX env must not redirect explicit -S -> disposable unrelated pane IDs/PIDs unchanged through experiment. |
| `missing-read-only-no-start` | pass | Missing socket query with -N -> exit 1, no socket created. |
| `endpoint-negative-controls` | pass | Native regular-file/overlong endpoint errors; symlink must be detectable -> both errors exit 1; **native tmux follows symlink successfully**. Caller must reject aliases using lstat/path-boundary checks, not assume -S authenticates. |
| `denied-is-not-absent` | pass | No-search-permission private directory -> query exit 1, underlying owned server socket preserved. Exit status alone does not classify absence versus denial. |
| `protected-drift-detection`, `missing-protected-hook-observable` | pass | Deliberately change option/remove synthetic hook -> observable drift/missing controlled command; no repair attempted. Not an implemented safety refusal. |
| `startup-only-executable-config` | pass | Two controlled scratch servers each execute synthetic startup line once; changed `-f` on live client does not execute desired config -> count `xx`, original digest `synthetic-config-a`, no reload marker. No metadata execution or Lua adapter tested. |
| `external-only-bounded-observation` | pass | Zero attached clients still expose one synthetic known-agent child under verified workload; cap=1 must return unknown; stale attachment root rejected; same logical key deduplicates two attachment inputs -> one child/one dedup row; exact capture 37 bytes/two nonblank synthetic lines. Dedup is a set-of-inputs oracle, not discovery implementation. |
| `wrong-pane-observation-control` | pass | Wrong exact pane must not match root association/output marker -> association rejected and marker absent; no wrong-pane text logged. |
| `agent-replacement-invalidates`, `agent-child-exit-root-survives` | pass | Native input replaces child -> distinct child PID/start; then child-only exit -> root remains same, known-agent result becomes unknown. No status report is carried across replacement. |

## Required gaps and unsupported combinations

| Required subcase / gate | Status | Reason / next evidence |
| --- | --- | --- |
| Stable-Neovim + external-client real PTY scenario | **blocked** | Official stable v0.12.6 executable unavailable. Installed dev build is not an acceptable substitute; no installation authorized. Two ordinary PTYs establish only generic tmux behavior. |
| Actual phone-app compatibility | **untested** | Intentionally excluded, not inferred from ordinary PTYs or source docs. |
| Native conditional identity/attach/stop, concurrent presentation cleanup, hooks/respawn epoch ordering, final-group fence | **untested here** | Owned by #33. Sequential cleanup and synthetic hook stamp do not qualify any destructive boundary. |
| Concurrent initialization, ready-last publication, generation/protocol ownership trust, startup lock failure/crash points | **untested here** | #35/other controlling-lane evidence required. Probe markers are constant synthetic fixture labels, not ownership verification. |
| Wrong-owner directories, malicious ancestor replacement, full namespace ready/initializing/incompatible/unknown decision mapping | **untested** | Native endpoint errors and lstat observations are not a complete preflight implementation. Same-UID/root adversaries are outside isolation guarantee. |
| Missing/unparseable/older/newer tmux admissions | **untested** | Only installed 3.8 executed. Missing tools/unsupported versions must refuse in future code; no fallback. Newer version string alone cannot qualify capabilities. |
| Mouse/focus-in activity, remote transport loss/host-login cleanup | **untested** | Keyboard, attach, resize, native detach and SIGKILL tested; no terminal emulator/transport focus injection or host policy claim. |
| Long-duration shell state/cwd, hidden Neovim buffers, editor layout retention | **untested** | Short-lived generic shell/command lifetime checks do not replace editor release tests. |
| Cross-owner linked/moved windows, arbitrary unsupported shapes, missing true identity stamps | **untested** | Two-pane visibility tested only. Must preserve/report unsupported state; native-safety qualification required before mutation. |
| Protected digest drift permitting management only if all requirements pass; Lua raw-list validation/metadata prohibition; known nesting refusal/opt-in | **untested** | Native startup-only behavior and option/hook observability passed. No plugin policy/adapter exists. Raw executable hooks and nesting remain unsupported escape hatches, never safety bypasses. |
| Real agents, threaded/reparented/double-fork process trees; unreadable procfs; status classifier/expiry/manual-report precedence; Open/focus actions | **untested** | Fixture direct child only. Existing known-name heuristic is spoofable; no real agent credentials/program run. Bounds/stale/wrong-root controls return unknown; task children can miss concurrent exits or children of other threads. Inconclusive must stay unknown, not confident absence/status. |
| Agent replacement/capture adversarial race and workload epoch association | **untested** | Before/after PID/start checks narrow association but are not atomic; identity/epoch and process reuse must be covered by the other gate and future implementation. |
| Durability/recovery, editor/API/storage/UI regression/release matrix | **untested here** | No feature code, snapshot, package, tracker/map, or unrelated service/workload changed. |

No runtime primitive tested here demonstrated an unavoidable backend incompatibility.
However, the missing supported Neovim build and required untested cases remain
blocking evidence gaps, not warnings. A reviewer must not close #34 as a complete
pre-handoff pass solely on these subset results. If another lane cannot establish
the native safety primitives, a new human design decision is required rather than
weakening the contract or interpreting this successful generic probe as approval.

## Failure findings, crash points, and validation scope

- During disposable harness development, a hook using literal `-t "#{hook_pane}"`
  failed: target argv is not automatically format-expanded. Final capability hook
  uses the hook's default pane target. This is not a safe general identity-hook design.
- Initial exit oracle used `display-message -p -t <stale pane>` exit status, which
  returned success via fallback. Final oracle enumerates exact pane IDs and checks
  that both root PID/start identities ended. Never infer target existence from that
  display command's exit code. Guard/fallback proof stays in #33.
- Initial agent observation correctly lost a SIGINT-terminated child, so final fixture
  makes that synthetic child's SIGINT policy explicit. No application behavior is
  inferred from this fixture adjustment.
- Intentional crash point: SIGKILL of one attached client after making it latest;
  five final repetitions. Natural detach/reconnect and fixture child replacement
  are predicate-gated. No server-crash, hook-interleaving barrier, init race, storage
  crash, fault-injection, or power-cut run was made. Cleanup `kill-server` is only
  scratch disposal, never a production stop proposal.
- `probe.py`: final SHA-256 `f24de9d61b1f78ab2aa147b15348f47fc0ea41453b4dc5e2dd85e8efa5772787`.
- `system_isolation.py`: SHA-256 `2818aac6f4f038e2711c111bed8e11bae4a8546cee0f1c60f10f16540f6c4140`.
- Python AST validation passed for both assets; `git diff --check` passed. No Lua was
  added/changed, so StyLua is not applicable. `sh tests/run.sh` was not run: no plugin
  implementation changed, and installed Neovim is not the required stable build.
- Tooling worked in this native session (`gh`, shell, ordinary bounded reads, PTYs,
  namespaces). No agent-runtime failure or alternative runtime was used. No PR,
  merge, issue comment/closure, generated snapshot or package installation occurred.
