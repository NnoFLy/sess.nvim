# Persistent terminal attachment: tmux feasibility

Research for [#25](https://github.com/NnoFLy/sess.nvim/issues/25), under
[map #24](https://github.com/NnoFLy/sess.nvim/issues/24). Accessed **2026-10-23 UTC**.
Throwaway research only; not an implementation specification or backend selection.

## Finding and evidence boundary

**tmux documents the required core capability:** a server owns the terminal and
workload independently of its attachment clients; sessions survive detach and
connection loss, and multiple clients can attach to the same session [M1]. Thus a
Neovim terminal and an existing phone terminal on user-managed secure access can
expose the **same live shell/AI process**, not restart copies, while that server
and workload remain alive. There is no material capability mismatch requiring
investigation of another backend. Only tmux was evaluated; exactly one backend
remains the product constraint, not a multi-backend abstraction.

Labels below distinguish **documented** contracts, **source observations**,
**implications** (reasoning, not decisions), and **untested** compatibility.
Local backend/editor version inspection ran only `tmux -V` (**3.8**) and `nvim --version`
(**0.13.0-dev-d714648-dirty**). No server, socket, attachment, remote connection,
or workload experiment was created; no user workloads were listed or controlled.
All runtime behavior below is untested here. Documentation establishes feasibility,
not end-to-end acceptance of a particular phone, agent, or Neovim configuration.

## Baseline, hosts, installation, license, maintenance

- **Documented:** tmux 3.8 README lists OpenBSD, FreeBSD, NetBSD, Linux, macOS,
  and Solaris; native Windows is not listed. WSL/other environments are not
  qualified by this research. Dependencies include libevent 2.x and ncurses;
  source builds additionally need a C compiler, make, pkg-config and yacc/bison
  [R]. Users must provide tmux, a suitable terminal/terminfo environment, and
  secure access to the host. No installation or connectivity work is proposed.
- **Observed upstream:** GitHub reports latest release **3.8**, published
  **2026-09-09** [REL]. The inspected 3.8 tag resolves to commit
  `7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`; citations pin that source, rather
  than tracking master. Its manpage carries September 23, 2026 as its date.
  Upstream master also had commit `939e8e65b685ca4cafb80ac659c7af28578a2fcf`
  dated October 23, 2026 [ACT]. These are maintenance evidence, not a support SLA.
- **License:** COPYING contains the ISC permission/disclaimer; README says files
  carry their own copyright/license notices. The inspected manual/server/spawn
  headers use ISC-style terms [L], [R]. This is not an audit of every bundled file
  or dependency. No tmux code is copied into Sess.
- **Unresolved:** minimum supported tmux/Neovim versions and target host matrix.
  Evidence for 3.8 is not a claim that every older release supports these flags.

## Capabilities and limits

| Area | Evidence and consequence |
| --- | --- |
| Detach versus stop | **Documented:** `detach-client`/default `C-b d` disconnect a client; the session persists. `kill-pane`, `kill-window`, `kill-session`, and `kill-server` are destructive, with different scope [M1], [M2], [MK]. Client termination is not workload termination. |
| Survival conditions | **Documented/source:** `destroy-unattached` defaults off; `exit-unattached` defaults off; `exit-empty` defaults on [M5], [O]. User config, hooks, explicit kill commands, workload exit, or host logout/process-cleanup policy can invalidate survival even while the host runs. Supporting arbitrary settings cannot be assumed. |
| Independent creation | **Documented:** `new-session -d` creates without attaching; `-c` sets start directory; `-P -F` returns identifiers. No command normally creates a login shell via `default-shell`, unless `default-command` changes it. Shell selection starts with suitable `$SHELL`, passwd shell, then `/bin/sh` [M3], [M5]. “Default shell” semantics therefore need an explicit product contract. |
| Provided command | **Documented:** a single `shell-command` argument runs through `default-shell -c`; multiple arguments can execute directly without a shell [MX]. Shell-text versus argv is a real distinction, not something tmux decides for `:Sess term [command]`. A one-element executable list must not be assumed to use the multiple-argument path. |
| Neovim embedding | **Documented composition:** Neovim `jobstart(argv, {term=true})` runs a program in a PTY-backed terminal buffer, defaults its dimensions to the window, and uses `xterm-256color`. tmux attaches in the current terminal [N], [NJ], [M2]. This provides a normal full-screen tmux client, not a new terminal protocol. Normal-mode escape/mappings remain Neovim behavior. **Untested:** rendering, key protocols, mouse, clipboard/passthrough and resize under actual user configurations. |
| Concurrent clients | **Documented:** any number of clients can connect [M1]; `attach-session` without `-d` does not evict existing clients. Do not use `-d`/`-x` for simultaneous attachment [M2]. Both writable clients feed the same terminal: **implication:** input can interleave, including Ctrl-C. There is no independent shell, collaborative editing arbitration, or per-client command transaction. **Source observation:** client key handling routes input to the session's active pane [C]. |
| Shared navigation | **Documented:** session current-window/active-pane state is shared; upstream FAQ describes linked/grouped sessions for independent current windows [FAQ]. This is not independent copies of the process. Whether Sess permits extra panes/windows/groups is undecided. |
| Resize | **Documented/source:** a pane has one geometry, not a separate application layout per viewer. `window-size` supports latest (3.8 default), largest, smallest, manual; client flag `ignore-size` removes that client's influence. `attach -r` combines read-only and ignore-size [M2], [M6], [O]. A phone can change the application's dimensions under latest; a smaller viewer may see only part of a larger window. Resize/input policy needs user choice and later compatibility tests. |
| Nested tmux | **Source observation:** attachment checks `TMUX` and whether the attaching terminal is a pane of that server, then may reject with “sessions should be nested with care, unset $TMUX to force” [C], [A]. Neovim's additional PTY means that exact check need not always trigger. Explicit socket routing avoids implicit server selection, but does not solve prefix-key collisions or terminal capability issues. Unsetting `TMUX` bypasses a guard, not proof of safe nesting. Outer/inner prefixes and Neovim mappings require testing; no automatic bypass policy is selected. |
| Exit/status | **Documented:** `pane_dead`, `pane_dead_status`, `pane_dead_signal`, `pane_pid`, `pane_current_command`, and `pane_start_command` support inspection [M7]. `remain-on-exit` can retain a dead pane; otherwise it normally disappears. `respawn-pane` starts a new process, and `-k` kills an existing one [M6], [MP], [O]. Attachment job exit status is not the workload's exit status. Retention/status UX remains undecided. |

## Identity, discovery and loss

**Documented:** tmux session IDs `$N`, window IDs `@N`, and pane IDs `%N` are
stable for their object's life **in that server**, unlike renameable names or
movable indices. `TMUX_PANE` exposes the pane ID to its child. `list-sessions`,
`list-windows`, `list-panes`, `list-clients`, and `display-message` support formatted
discovery [M8]. A tmux session is a backend object, not a Sess saved session or
session snapshot.

**Source observation:** IDs use server-memory counters [I], [IW]. A restarted server
can reuse the same IDs; a deleted name can be recreated. `new-session -A` attaches
if the name exists, so it cannot authenticate ownership [M3]. A live pane can also
be respawned with a different workload while keeping its identity [MP].

**Implications, not chosen design:** records need enough server-incarnation and
owned-object evidence to distinguish an intended terminal from reused IDs/names.
Namespace prefixes and metadata can help avoid mistakes but are not security
boundaries against the same OS user. Omitted targets select contextual/recent
objects; names accept prefixes/globs unless exact matching is requested [M8].
Never use that fallback to attach or stop a supposedly owned workload. Explicit
socket plus verified exact object targeting, and rejection of stale/ambiguous
records, are necessary safety questions for the lifecycle design.

**Native external discovery/attachment:** after the user has independently
obtained a host terminal with appropriate OS identity/access, tmux itself offers
these commands. Illustrative only, **not executed**; `$socket` is the known socket
of the intended server and `'$N'` stands for its verified literal session ID:

```sh
tmux -N -S "$socket" list-sessions -F '#{session_id} #{session_name}'
tmux -N -S "$socket" attach-session -t '$N'
# C-b d detaches this client with default bindings.
```

`-N` forbids starting a missing server [M9]. Discovery is per server/socket, not a
global registry of every tmux instance. Publishing the correct socket/target to a
human is a UX decision, not phone connectivity or permission to enumerate other
servers. No mobile app, new network listener, authentication scheme, or tunnel is needed
from Sess.

**Backend loss is different from detach.** The manual distinguishes lost PTY,
server shutdown/crash and normal detach messages [M10]. Reopening Neovim can
reattach only if the original server and workload survive. tmux does not restore
that live process after server loss or reboot. Some orphan processes might remain
OS-visible; that is not recovery of their original terminal. A missing socket
alone is not proof of a dead workload: the manual documents recreating an
accidentally removed socket using SIGUSR1 to the known server [M9]. Automatic
signaling/recreation is not authorized here. Missing executable, denied access,
missing socket, missing object and dead pane should not silently become a newly
started command. Recovery/retry/restart policy belongs to a decision ticket.

## Security and agent visibility

- **Documented:** tmux uses a local Unix-domain socket, not a remote network
  service. `-L` selects an independent server name in its UID-specific directory;
  `-S` selects a full alternative socket path. The default directory must not be
  world accessible [M9]. **Source observation:** server startup binds AF_UNIX
  and unlinks the chosen socket pathname [S]. Validate any persisted/user-provided
  socket path before invoking potentially server-starting commands; never probe
  an unrelated path by creating a server there.
- **Documented:** default access is the server owner and root. Cross-user access
  needs deliberate filesystem permission changes plus `server-access`; upstream
  warns against untrusted users even read-only [M11]. For the phone, secure
  transport and authorized host identity remain user-managed assumptions. A
  private namespace prevents accidental cross-server control, not malicious
  same-UID code. Root is not excluded. `attach -r` is a client interaction mode,
  not a sandbox for a user who can separately reconnect writable.
- **Implication:** scope listing/stopping to the chosen socket and verified owned
  objects; no default-server fallback, broad `kill-server`, or “cleanup” of
  ambiguous records. A server could contain unrelated workloads unless ownership
  rules forbid that. The server/namespace ownership policy is still open.
- **Documented injection boundaries:** Neovim argv-list execution avoids the
  outer shell [NJ], but tmux still has command grammar, flags, targets, formats and
  special semicolon handling; embedded command strings can be reparsed [M4]. Do
  not concatenate names, paths or metadata into tmux command/config strings,
  `run-shell`, hooks, or format expressions. Use controlled syntax, validated
  targets, argv boundaries, option termination where supported, and tmux-aware
  literal escaping for semicolon arguments. Intentionally executing user command
  text is distinct from accidentally executing a saved name. Exact parser and
  hostile-input tests await the shell-text/argv decision.
- **Source observation:** tmux server code forks the pane workload, whereas
  Neovim `jobpid` identifies the attachment job [P], [NJ]. Sess's existing
  `process_probe.job_agent()` searches the job command and descendants starting
  at that PID [REPO]. The actual AI process is not generally a descendant of
  the tmux attachment client. `pane_pid` can provide the first pane process;
  `pane_current_command` is best-effort and not a process tree or agent status
  contract [M7]. `capture-pane` can inspect backend terminal contents [MC].
  **Implication:** current detection cannot be assumed to discover these agents;
  explicit owned-pane/process association and terminal-observation semantics need
  investigation. Detached output, shared views, command/title spoofing and PID
  reuse make command names or rendered text insufficient proof of identity/status.
- **Repository boundary:** session snapshots do not promise live processes;
  Neovim documents restoring terminal buffers by restarting their command [N].
  Current unload safety treats terminal jobs as stoppable jobs [UNLOAD]. Distinguishing
  an attachment from its workload must not weaken ordinary-terminal confirmation
  or allow snapshot replay to recreate a missing workload silently.

## Concrete follow-up decision/test topics (not created here)

1. HITL: choose the single backend and minimum versions/hosts, then decide server
   ownership, socket namespace, safe incarnation/terminal identity, and external
   discovery UX. Backend choice remains open despite tmux feasibility.
2. HITL: define `[command]` parsing/default-shell rules; detach versus explicit
   stop on exit, unload, deletion and snapshot restoration; and missing/dead/
   replaced-backend behavior without silent restart or loss of live state.
3. HITL: choose concurrent-input and geometry policy, plus user-config/nested-tmux
   compatibility boundaries (including what settings may be required or overridden).
4. Focused investigation/acceptance: preserve PID across Neovim exit/reopen and
   abrupt client loss; simultaneous input/resize from two PTYs; nested tmux;
   permission denial, corrupt/stale identifiers and server replacement; normal
   and signaled workload exits; hostile command/identifier arguments; and owned
   agent detection/focus/status. No phone provisioning is needed to test two PTYs.

These are bounded downstream decisions/tests, not reasons to investigate another
backend or to promise every terminal/agent/configuration combination now.

## Primary sources

All accessed 2026-10-23. tmux links below pin **3.8 source commit**
`7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`. Neovim references pin **v0.11.4**
documentation (not the locally installed development build). FAQ is a mutable
upstream wiki observation as of access date. Repository context pins the starting
Sess commit `eee53cca450a1e1a64e47ebe43f507fe85669dd0`.

[M1]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L35-L95
[M2]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L1065-L1245
[M3]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L1321-L1440
[M4]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L418-L645
[M5]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L4904-L5283
[M6]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L6250-L6370
[M7]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L7435-L7478
[M8]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L767-L950
[M9]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L161-L210
[M10]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L8904-L8942
[M11]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L1595-L1656
[R]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/README
[L]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/COPYING
[REL]: https://github.com/tmux/tmux/releases/tag/3.8
[ACT]: https://github.com/tmux/tmux/commit/939e8e65b685ca4cafb80ac659c7af28578a2fcf
[O]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/options-table.c
[C]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server-client.c
[A]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-attach-session.c#L68-L98
[I]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/session.c#L29-L30
[S]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L107-L153
[P]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L477-L574
[MX]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L983-L1023
[MK]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L3305-L3338
[MP]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L3926-L3978
[MC]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L2798-L2870
[IW]: https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/window.c
[N]: https://github.com/neovim/neovim/blob/v0.11.4/runtime/doc/terminal.txt
[NJ]: https://github.com/neovim/neovim/blob/v0.11.4/runtime/doc/vimfn.txt#L5343-L5466
[UNLOAD]: https://github.com/NnoFLy/sess.nvim/blob/eee53cca450a1e1a64e47ebe43f507fe85669dd0/lua/sess/unload.lua
[FAQ]: https://github.com/tmux/tmux/wiki/FAQ
[REPO]: https://github.com/NnoFLy/sess.nvim/blob/eee53cca450a1e1a64e47ebe43f507fe85669dd0/lua/sess/agent/process_probe.lua#L325-L341
