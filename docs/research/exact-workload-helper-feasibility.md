# Short-lived helper / exact workload termination

**Outcome: NOT QUALIFIED; no complete compliant recipe demonstrated.** A
short-lived helper can signal and observe one pinned process, but that is not
whole-workload consent, containment, native tmux epoch atomicity or attachment
safety. This is negative/inconclusive research, **not proof that every stock-tmux
solution is impossible**. In particular, stock tmux has an optional systemd
birth-placement path that deserves separate qualification if explicitly approved.

Research and corrective writer reruns collected 2026-10-27 UTC for
[Investigate short-lived helper feasibility for exact workload termination](https://github.com/NnoFLy/sess.nvim/issues/39),
map [Persistent terminals across Neovim and mobile clients](https://github.com/NnoFLy/sess.nvim/issues/24).
Sole writer; branch
`research/exact-workload-helper-feasibility`, baseline
`eee53cca450a1e1a64e47ebe43f507fe85669dd0`. Evidence only: no feature code,
architecture adoption, dependency installation, PR or merge.
The [independent review](exact-workload-helper-independent-review.md) accepts
publication as **negative/inconclusive evidence only**, not a safety-gate pass.
After cleanup and reporting corrections, the reviewer independently reran both
the six-subset counterexample suite and the two cleanup controls; results matched.
The review preserves its initial findings and records the corrective recheck.
Collection-time pending-review metadata remains historical, not current status.

## Controlling evidence and contract

Read full bodies/comments of the investigation and map above, the three named
contracts below, originating
[Qualify native tmux identity and attachment safety](https://github.com/NnoFLy/sess.nvim/issues/33),
and [Choose the single persistent terminal backend and support boundary](https://github.com/NnoFLy/sess.nvim/issues/28).
Snapshot/comment hashes, ticket titles and source provenance are in
[sources.json](probes/exact-workload-helper/sources.json).

- [Resolve native workload identity and termination blockers](https://github.com/NnoFLy/sess.nvim/issues/37#issuecomment-6392147738)
  resolution authorizes bounded short-lived-helper investigation only. A workload
  includes background/disowned descendants; attachments are excluded. The primary
  checkout's uncommitted `GLOSSARY.md` supplies that definition; it was read, not
  copied into or modified from this committed-baseline worktree.
- [Define persistent terminal acceptance criteria and validation evidence](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573)
  acceptance requires source-backed adversarial evidence, exact consent, native
  arrivals, termination verification and joint attachment guards. Its later launch-only
  refinement does not weaken those requirements.
- [Choose a fail-closed persistent workload launch boundary](https://github.com/NnoFLy/sess.nvim/issues/38#issuecomment-6428416860)
  final resolution selects source-built C/private-socket **launch**, with
  native-style acceptance and a final-cwd-check race limit. It does not approve termination containment,
  systemd, ptrace, privileges or an additional launch wrapper. Python below is
  disposable test tooling, not a proposed product dependency.
- [Immutable native evidence](https://github.com/NnoFLy/sess.nvim/blob/d4e35f27ae1d76258611c815e2c83ef4f3e5a9c4/docs/research/persistent-terminal-native-safety.md)
  and [Qualify native tmux identity and attachment safety — independent review checkpoint](https://github.com/NnoFLy/sess.nvim/issues/33#issuecomment-6391731226)
  establish partial counterexamples: HUP-ignoring root survival, delayed hook
  stamps and presentation-only acceptance after anchor loss. Review inspected
  code/sources/retained runs, **did not independently rerun probes**, corrected
  stable-Neovim availability and weak parser controls, and explicitly left the
  gate open. Historical full-run and corrected parser counts must not be merged.

The unchanged destructive-boundary conjunction is **server generation + owner
ID/incarnation + context + terminal + exact canonical anchor/group/window/pane and
supported shape + workload epoch + root PID/start identity + exact copied
consent**. New/replacement/unconsented workloads and unrelated processes must
survive. Whole-workload exit and final disappearance of the exact owner group,
including presentations, are separate postconditions. Neither substitutes for
the other. Missing/unreadable/malformed/unsupported/ambiguous evidence refuses;
committed effects remain pending/partial/unknown, with **no automatic retry**.

## Primary mechanisms: capabilities and precise gaps

All tmux source links pin upstream 3.8 commit
`7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`; installed binary provenance is
[recorded](probes/exact-workload-helper/runtime.json), not a reproducible-build
claim. Linux interfaces below use locally installed **Linux man-pages 6.19-1**,
with attributed, numbered [verbatim excerpts](probes/exact-workload-helper/source-excerpts.txt)
and full uncompressed input hashes. The versioned upstream
[6.19 release archive](https://www.kernel.org/pub/linux/docs/man-pages/man-pages-6.19.tar.xz)
is a provenance reference; it was not downloaded/byte-compared. Do not mistake
local package text for a verified upstream Git blob.

| Candidate | Source-backed capability | Missing obligation / support assumption |
| --- | --- | --- |
| `/proc` PID/starttime and pidfd | `pidfd_open(2)` (Linux 5.3), `pidfd_send_signal(2)` (5.1), pollable task exit; lifetime handle avoids retargeting a later PID occupant. | Acquisition must itself bind consent to the intended live task; sampling first is not atomic. A handle covers one task/thread group, not historical descendants or a tmux pane epoch. Permission/namespace/syscall availability still apply. No root/capability assumption. |
| Process tree, PGID/session, TTY, environment labels | `kill(2)` scopes a numeric group, not ancestry; group success can mean only one signal delivered. | Descendants can detach/reparent; root exit loses current ancestry. Fixture D1 has different PGID/session and no live root. Shared TTY/cgroup/labels are not ownership proof. No broad enumeration or group kill is justified. Linux 6.9 pidfd process-group signalling does **not** turn a mutable PGID into a workload boundary. |
| Late cgroup migration, freeze, then kill | `cgroups(7)`/`clone(2)` document inheritance, process migration, delegation and populated/frozen observations. | Moving a root after execution cannot retroactively recover escaped descendants. Freezing an unknown/shared cohort cannot establish membership; even reversible stops disturb unconsented work. Direct writes require delegated access and migration permissions. `populated=0` is not a permanently closed admission fence. No cgroup writes/freezing performed. |
| Birth-time private cgroup + recursive kill | `CLONE_INTO_CGROUP` (Linux 5.7) can create directly in a selected v2 cgroup, subject to access restrictions; descendants inherit. | Strong candidate **if** every native birth/respawn enters the right separately identified domain before workload execution, escape/unrelated migration is fenced, and consent binds that domain. A new wrapper only for editor launches misses native phone births. Kernel `cgroup.kill` atomicity/limits were **not source-qualified in this run** (fetch blocked below); no claim of a qualified kill recipe. |
| **Stock tmux optional systemd cgroups** | [spawn.c:478–519](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L478-L519), [compat/systemd.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/compat/systemd.c), [configure.ac:490–531](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/configure.ac#L490-L531): systemd-enabled build defaults cgroups on unless disabled; child requests a random transient scope before exec, including the common respawn path. This can cover helper-free native creation without a new launch wrapper. | **Promising, unqualified**, not absent from stock source. Requires libsystemd, accessible user bus/manager and suitable cgroup policy; not selected dependencies. Placement errors are logged and execution continues. Parent publishes pane/hook before child placement is necessarily complete. Scope description binds child/server numeric PIDs, not full Sess generation/epoch/start tuple; root exit before association, scope reuse/collection, failed/timed-out placement and migration need proof. No successful configured-manager probe or containment enforcement was authorized/executed. |
| ptrace at stop time | `ptrace(2)` documents SEIZE/INTERRUPT and fork/vfork/clone tracing options; future children can be auto-traced. | Attaching now cannot discover already detached historical descendants. Monitoring every birth from launch changes the authority/lifetime boundary (or requires pre-existing containment). UID alone does not assure access: dumpability, LSM/Yama, credentials and existing tracer matter. EXITKILL can kill tracees on helper crash, not a safe ambiguity policy. No tracing or policy change attempted. |
| tmux queue, `run-shell`, cooperative locks, server suspension | [cmd-run-shell.c:110–206](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-run-shell.c#L110-L206), [cmd-queue.c:704–784](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-queue.c#L704-L784), [server.c:266–284](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L266-L284): a fixed non-WAIT format/command sequence excludes ordinary competing tmux client mutations. External helper execution returns WAIT for its queue, not a server-wide mutex. | Q1 deterministically admits another native client's workload while helper waits. Native clients do not honor an editor/helper lock. Suspending the server does not reconstruct historical descendants and introduces crash/resume hazards; no such mechanism qualified or adopted. No source-proven full-tuple/process-containment destructive transaction found. |

### Important stock-systemd qualification limit

The installed binary **does** link libsystemd and import the cgroup-related sd-bus
functions ([linkage.json](probes/exact-workload-helper/linkage.json)). Therefore
neither “Linux lacks unprivileged cgroups” nor “stock tmux cannot place native
births” is a valid conclusion. The isolated probe supplies no XDG_RUNTIME_DIR or
user-bus environment; the three sampled synthetic processes (root and detached
child of one workload, plus an unrelated second workload) shared one inherited
cgroup. This proves **no successful segregation in that invocation**, not why it
failed nor failure under a properly configured user manager. No explicit user
manager/cgroup calls were made by the harness; native tmux retains its compiled
behavior. Successful-manager paths, systemd version/policy and direct kill
permissions remain untested, not silently required.

The optional implementation waits for a matching `JobRemoved` path, but its
handler reads only job ID/path, not a successful job result. Regardless, caller
`spawn.c` continues after a negative placement return. A preflight demonstration
that one scope worked is not a guarantee for a later native birth. A future
candidate would need fail-closed **admission to management**, durable attribution
through root exit, separate replacement scopes and a native destructive-boundary
fence; it cannot treat this best-effort feature name as complete containment.

## Why the gap matters

A stop-time-only snapshot has no complete creator-history proof after a child
has detached and its parent exited. D1's oracle knows the child **because the
synthetic fixture reports it before exit**; a production helper does not gain
that knowledge from the pane PID. Two different ancestry histories can have the
same presently observable parent/group/session attributes. That is an
information gap for snapshot-only recipes, not a theorem ruling out birth-time
kernel containment, a separately qualified native facility or another approved
constraint change.

The missing composite is: **birth-bound, escape-resistant and lifetime-stable
per-workload membership (including native creation/respawn), plus an exact
consent/epoch fence spanning verification and irreversible process effects**.
A pidfd supplies only one component. The launch-only helper selected by
[Choose a fail-closed persistent workload launch boundary](https://github.com/NnoFLy/sess.nvim/issues/38)
is not that composite. Even a perfect process-domain stop would still need the
final exact tmux-group disappearance fence; an unconsented native arrival must be preserved
and reported as remaining work, never swept away to force that postcondition.

### Separate attachment gate

Process handles/cgroups do not validate canonical anchor existence, presentation
role/ownership, exact membership or server generation. Joint canonical-anchor +
presentation + group + generation checks are still mandatory **both at creation
and actual attachment**, including exact IDs/nonempty markers, CANFAIL fallback,
server replacement and malformed tagged responses. `has-session` then create,
presentation-only guards and command exit zero are insufficient. The immutable
A05/A08/A10/A11 controls remain relevant; this run did **not** implement or rerun a
complete attachment recipe. A process-helper result cannot pass that gate.

## Disposable probe evidence

[probe.py](probes/exact-workload-helper/probe.py) and
[observed.json](probes/exact-workload-helper/observed.json): **one corrected-version
counterexample run, six subsets; two narrow passes and four failed safety
properties detected; harness exit 0**. Separately, **one cleanup-control run with
two injected-failure cases passed, exit 0**. F1/F2 are harness checks, not two more
product safety passes. Both commands were run by the writer after code/source
inspection and then independently rerun by the reviewer with matching results.
Writer and reviewer runs are separate evidence; their counts are not combined.

Metadata for the pre-correction writer run and one intermediate correction run
(before the explicit SIGCHLD precondition/watchdog-ready handshake) are retained
separately in the JSON; their observations agree but **counts are not combined**.
The still earlier pre-I/O-bound run is disclosed only in runtime history. A successful
normal run alone is **not evidence of exceptional-path cleanup safety**; only the
two named injected paths were exercised. No stress-count argument or complete
gate pass. Runtime: Linux
7.2.10-arch1-1 x86_64, tmux 3.8-1, Python 3.14.8-1, glibc
2.44+r50+g1848099f063e-1. This is not Neovim/PTY release qualification.

| Required subset | Status / bounded observation |
| --- | --- |
| D1 descendants/background/root exit | **fail** for root/window/tree/group recipes: forked child calls setsid, ignores HUP, redirects stdio, reparents after root exits, survives exact window removal. Unrelated synthetic workload survives. Literal interactive-shell `disown` is **untested**; detached descendant semantics are exercised. |
| C1 inherited containment | **fail** for using the inherited cgroup as one workload: root, detached child and unrelated synthetic workload share it. No contents enumeration, migration, recursive kill or freeze tested. |
| E1 respawn before hooks | **fail** for inline hook epoch: same native client queue sees old stamp after respawn with changed PID; later invocation sees changed stamp. Fixed queue ordering, no timing lottery. |
| P1 PID/start identity | **pass only** for held pidfd targeting: signal old HUP-ignoring root; witness exit; replacement and unrelated workload survive. Fixture PID/start samples bind the test oracle, not a general acquisition algorithm. Actual PID reuse **untested**, never forced; complete root-start consent/epoch binding **blocked**. |
| Q1 native arrivals/helper interval | **fail** for treating `run-shell` as a global lock: helper explicitly signals ready, waits on release; second native client creates workload before release. Ready/release barriers, not sleeps proving exclusion. |
| X1 helper crash after effect | **pass only** for ambiguity counterexample oracle: helper signals an inherited victim pidfd then SIGKILLs itself without ack; test witnesses victim exit, others survive. This is not a tested journal/reconciliation protocol; effect-before-ack cannot be relabelled unattempted. |
| Anchor loss/stale/fallback/server replacement | **untested here**; prior immutable A05/A08/A10/A11 give partial source-backed counterexamples/controls, not full joint-guard qualification. No evidence of a new safe recipe. |
| Final exact-group disappearance/native arrival | **blocked as a full stop**; earlier immutable F01/F02/F04 cover group-fence subsets only. This probe does not construct owner/presentation deletion or claim termination from group absence. |
| Timeouts/malformed/unreadable/unsupported/ambiguous output, crash before/after each effect | **untested** as a product protocol beyond X1 and bounded calls. F1/F2 below exercise only two synthetic cleanup paths, not protocol recovery. No complete protocol exists to fault-inject. No fabricated timeout/recovery pass. Must preserve pending effects and refuse automatic retry. |
| Whole recipe under all concurrent native mutations, birth containment and late-root discovery | **blocked**, prerequisites above unqualified. No bulk kill, ptrace, cgroup kill or freezing experiment substitutes for them. |
| F1 setup exception after synthetic session creation | **harness-control pass**: intentional setup error surfaced; `__enter__` invoked cleanup; owned fixture/server exit witnessed, watchdog reaped and private directory removed only afterward. |
| F2 first-client drain exception during teardown | **harness-control pass**: injected error surfaced in an exception group; same client still waited/reaped, second client drained/reaped, remaining fixtures/server/watchdog cleaned independently. Not a simulated signal-permission failure or exhaustive teardown matrix. |

Reproduce with existing tools, from this worktree, exclusive private output:

```sh
umask 077
output=$(mktemp /tmp/sess-exact-observed.XXXXXX)
python3 docs/research/probes/exact-workload-helper/probe.py > "$output"
python3 -m json.tool "$output" >/dev/null
faults=$(mktemp /tmp/sess-exact-cleanup.XXXXXX)
python3 docs/research/probes/exact-workload-helper/probe.py --cleanup-faults > "$faults"
python3 -m json.tool "$faults" >/dev/null
# Compare output to current top-level results, and faults to cleanup_fault_checks.
# observed.json also retains separately labelled historical run metadata; do not sum it.
```

The harness creates a mode-0700 temporary root/HOME with private config/storage
and an explicit short private socket; all clients use `-N -S PRIVATE`. Only synthetic commands/data are
used, no normal socket/server, inherited environment dump, pane capture or broad
process enumeration. It reads bounded records for positively owned fixture PIDs
only. Fixture alarms retain the 30-second bound, including after fork;
setup/effect readiness uses explicit files.

**Cleanup correction:** the earlier daemon-start/`started` flag and unconditional
`TemporaryDirectory` removal were unsafe on setup/teardown exceptions. The
corrected fixture starts **foreground `tmux -D` with no command**, acquires the
unreaped direct child's pidfd, starts a disposable inherited-pidfd watchdog and
waits for its ready marker before creating workloads. The private endpoint must
report that same server PID. Primary evidence was inspected before use:
[tmux.1:125–135](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L125-L135)
specifies non-daemon mode/no command and disables `exit-empty`;
[tmux.c:433–435](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.c#L433-L435)
sets `CLIENT_NOFORK`, and
[server.c:189–194](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L189-L194)
skips the daemon fork. The watchdog waits up to 45 seconds for server exit, then
signals only that server's held pidfd if needed. This is disposable test-resource
supervision, **not** a proposed product supervisor, containment recipe or launch
wrapper for native workloads.

All setup exceptions invoke cleanup; teardown attempts each signal, client
drain/wait, server stop/wait and fixture exit/handle close independently and
surfaces accumulated errors. Signals use acquired synthetic pidfds or positively
owned unreaped `Popen` children, never socket discovery, arbitrary numeric PIDs or
process groups. Directory/socket removal requires known owned exits and no
pending birth association. Ambiguous state retains that directory/evidence; if
server exit is ambiguous, cleanup does not cancel the watchdog. No
`TemporaryDirectory` destructor unlinks it.
Normal-run and F1/F2 results each verify foreground server exit, watchdog exit,
tracked handles closed, direct clients reaped and directory removal afterward.

Untested: watchdog-expiry kill, harness hard-kill (especially before watchdog
installation), forced server-wait/signal errors, every setup failure boundary and
the retained-evidence ambiguity branch. The two injected paths do not establish
universal failure-safe cleanup, and this fixture is not a candidate workload-stop
implementation. System/user configuration isolation as a complete supported
recipe remains the gate in
[Qualify tmux isolation and multi-client behavior](https://github.com/NnoFLy/sess.nvim/issues/34),
not proved by this harness's private `-f` alone.

### Validation and retrieval failures

- Executed by writer: corrected probe command and separate `--cleanup-faults`
  command (both exit 0); Python AST parse; JSON syntax/count/hash checks;
  `git diff --check` plus `git diff --no-index --check` for each new untracked
  asset; read-only binary/package/source checks. See runtime/source
  records for hashes, separate run histories and the collection-time review fingerprint.
  The linked independent review records the later recheck and runtime reruns.
  New pinned `tmux.c`/`client.c` retrieval and the already retained tmux manual/server
  source support foreground supervision; no Linux source retry occurred during
  this correction. No Lua changes; StyLua not applicable. Application suite
  `sh tests/run.sh`, stable-Neovim scenarios and real multi-PTY matrix **not run**:
  no runtime implementation changed, and they cannot establish the missing
  primitives. Only lightweight targeted checks ran directly. HEAVY_HELD and
  HEAVY_SLOT were unset; no heavy command/admission bypass occurred. The first
  new-file whitespace validator incorrectly rejected no-index status 1 with no
  diagnostics (files differ). It stopped, was reported, and was corrected to
  accept only status 0/1 with empty diagnostics; all seven assets then passed.
- Pinned Linux v6.12 source
  [cgroup-v2.rst](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/Documentation/admin-guide/cgroup-v2.rst)
  retrieval via GitHub contents failed HTTP **429**, `gitmon refuses to schedule
  us: too-many-processes`. One supervisor-approved diagnostic retry confirmed it;
  approved same-pin raw URL also failed HTTP 429. That source lane stopped; no
  kernel implementation/`cgroup.kill` semantic qualification is claimed. Local
  man pages support only the narrower facts cited above.
- Guessed tmux root `systemd.c` returned HTTP **404**. Stopped and reported;
  supervisor approved bounded same-pin tree discovery, which found
  `compat/systemd.c`; that file and `configure.ac` fetched successfully. This is
  a source-navigation correction, not evidence of absence. No tools installed,
  arbitrary fetched code executed or security controls changed.

## Trust boundary, residual risks and next blocking decision

Backend markers/output, persistent identities, paths, peer processes and native
mutations are untrusted/fallible. The proposed product must not evaluate names
as commands/formats, trust a missing response, expose environment/command secrets
or expand copied consent. Here, fixed synthetic argv/config, private routing,
bounded calls, exact owned lifetime handles and no broad signals protect the
user's workloads. Private paths do **not** defend against hostile same-UID/root
code. This evidence does not grant new privileges or promise containment against
same-UID cgroup migration, set-ID workloads or arbitrary hooks.

**Suggested NEW blocking live-design question:** Given no demonstrated complete
recipe, will the human explicitly authorize a narrower **systemd/cgroup-qualified
stock-tmux support/dependency investigation**, retaining helper-free native phone
creation and all consent/attachment gates, or reopen some other precise existing
constraint? The former must first prove fail-closed management admission,
birth/respawn-domain attribution surviving root exit, escape/native-arrival
fencing, exact destructive epoch coordination and final group disappearance.
If it cannot, another explicit authority/containment change is needed; neither a
new wrapper, resident observer, patch, phone protocol nor weaker whole-workload
semantics is implicitly approved. Independent recheck accepted this evidence
with those limits. Track the next question as a blocking live-design decision;
do not close the safety gates as passed.
