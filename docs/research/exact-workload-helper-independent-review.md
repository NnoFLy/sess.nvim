# Independent review: short-lived helper feasibility

**Current recommendation after corrective recheck: safe to publish as reviewed
negative/inconclusive evidence, not a safety-gate pass.** The original three
findings are corrected. Both authorized independent synthetic commands passed;
cleanup qualification remains limited to the exercised paths. No complete
compliant termination/attachment recipe has been demonstrated; universal
impossibility has not been established. No architecture, dependency or production
implementation is approved by this review.

The initial review below is preserved as history; its line references and
no-rerun statements describe the pre-correction revision only. The dated recheck
at the end records the current code, actual independent runs and limitations.

Reviewed 2026-10-27 UTC in
`/home/nnofly/code/personal/sess.nvim/.worktrees/exact-workload-helper-feasibility`,
branch `research/exact-workload-helper-feasibility`, HEAD/baseline
`eee53cca450a1e1a64e47ebe43f507fe85669dd0`. The writer had finished. This reviewer
owns only this new file; all other assets remained unchanged. The primary
checkout is `/home/nnofly/code/personal/sess.nvim`. This is a disposable research
asset with no integration target; commit, push and tracker authority remain with
the parent. No children, PR, merge, installation or tracker mutation.

## Initial review scope — 2026-10-27 UTC (historical)

Read the worktree skill, repository instructions, issue-tracker/domain guidance,
committed glossary, then-current [feasibility report](exact-workload-helper-feasibility.md),
and **all six** assets in `probes/exact-workload-helper/`: `probe.py`,
`observed.json`, `runtime.json`, `linkage.json`, `sources.json` and
`source-excerpts.txt` (seven reviewed assets including the report).

Fetched and read full bodies/comments of these named contracts as data:

- [Investigate short-lived helper feasibility for exact workload termination](https://github.com/NnoFLy/sess.nvim/issues/39).
- [Persistent terminals across Neovim and mobile clients](https://github.com/NnoFLy/sess.nvim/issues/24).
- [Resolve native workload identity and termination blockers](https://github.com/NnoFLy/sess.nvim/issues/37#issuecomment-6392147738).
- [Define persistent terminal acceptance criteria and validation evidence](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573), including its later launch-only refinement.
- [Choose a fail-closed persistent workload launch boundary](https://github.com/NnoFLy/sess.nvim/issues/38#issuecomment-6428416860).
- [Qualify native tmux identity and attachment safety](https://github.com/NnoFLy/sess.nvim/issues/33), including the independent-review checkpoint.
- [Choose the single persistent terminal backend and support boundary](https://github.com/NnoFLy/sess.nvim/issues/28).

Independently retrieved stock tmux source at
`7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`: complete `compat/systemd.c`,
`spawn.c` and `configure.ac`; inspected the cited queue/WAIT sections in
`cmd-queue.c`, `cmd-run-shell.c` and `server.c`. All six full-input SHA-256 values
match `sources.json`. Read retained local man-page excerpts; independently
matched all seven uncompressed local manual hashes and checked
`proc_pid_stat(5):227–233` for starttime field 22. These are local package inputs,
not independently byte-compared upstream man-pages release contents.

Read the [immutable native-safety report](https://github.com/NnoFLy/sess.nvim/blob/d4e35f27ae1d76258611c815e2c83ef4f3e5a9c4/docs/research/persistent-terminal-native-safety.md),
its historical observations, corrected parser observations and regression-control
JSON, and the `creation_attachment`/`epochs_and_stop` probe bodies. Historical
31-case counts and corrected seven-case parser counts remain separate. Neither
that earlier independent review nor this review independently reran those probes.

Not independently inspected: the other four tmux inputs listed in this run's
manifest, full prior fencing/parser implementation, upstream man-pages archive,
Linux cgroup-v2 source/kill implementation, configured systemd-manager behavior,
or the primary checkout's uncommitted glossary. The controlling resolution
itself confirms inclusion of background/disowned descendants. No failed Linux
source retrieval was retried by this reviewer.

## Initial findings — all corrected on recheck (historical)

### Medium — cleanup was not guaranteed; original runtime rerun blocked

`probes/exact-workload-helper/probe.py:85–110,142–160` starts a server with
`exit-empty off`, `exit-unattached off` and retained exited panes. A timeout in
initial `new-session` can leave the server started before `started=True`; failure
in the following `set-hook` also escapes `__enter__`. Python does not invoke
`__exit__` when `__enter__` raises. No server lifetime bound is installed: fixture
alarms and the initial 25-second sleep do not bound the server. Within
`__exit__`, an exception from signalling, `communicate`, `kill-server` or an exit
wait skips subsequent cleanup. Temporary-directory removal is not server
termination.

The successful writer-run cleanup string is plausible for its normal path, but
cannot establish failure-safe boundedness. Accordingly **the unchanged probe was
not executed**. Parent should require focused cleanup correction and a separately
authorized rerun; this reviewer did not patch or wrap the probe. This is a
synthetic-resource leak risk, not evidence that the probe targets live user jobs.
The feasibility report's cleanup description at lines 168–170 needs this limit.

### Low — original issue references violated the naming convention

`exact-workload-helper-feasibility.md:10–44` and later prose use bare issue
numbers/number-labelled links. Before publication, use actual ticket/map titles,
as required by the assignment's Wayfinder convention. This does not change the
mechanism findings. This review uses named links instead.

### Low — original containment wording confused processes with workloads

`exact-workload-helper-feasibility.md:83` says “all three sampled synthetic
workloads.” `probe.py:168–177` samples the root and detached child of **one**
workload plus an unrelated workload: three processes, two workloads. Correct that
wording; the shared-cgroup counterexample itself is valid in scope.

## Initial substantive assessment — remains applicable

- **Stock systemd path exists; it is not a qualified solution.** At the pinned
  source, `configure.ac:490–531` requires explicitly enabled systemd support and
  defaults cgroups to that selection unless disabled. `spawn.c:478–513,577–595`
  places the request in the child before intended exec, while the parent can
  publish the pane/event without waiting; respawns share this path.
  `compat/systemd.c:123–150,157–174,189–238,281–346` uses the user bus and a random
  transient scope with numeric child/server attribution. Its JobRemoved handler
  (`84–103`) does not check job result; spawn continues on negative placement
  return. The timeout branch also does not explicitly assign a negative result.
  These are best-effort admission limits, not proof of every placement failing.
- **No observed separation is not a diagnosed placement failure.** The harness
  omits user-bus/runtime-directory environment. The recorded shared membership
  proves only that the sampled processes were not segregated in that invocation;
  there is no captured placement error establishing why. I independently checked
  the binary hash, ELF libsystemd dependencies/imports and package tuple. Imports
  do not alone prove ENABLE_CGROUPS build flags or successful scope creation.
  A configured-manager experiment, policy/delegation, escape/migration controls,
  scope attribution after root exit and kill permissions remain unqualified.
- **pidfd evidence is correctly narrow.** Stable handles avoid later PID
  retargeting after acquisition, not consent-to-handle acquisition races, tmux
  epoch binding or whole-descendant coverage. The fixture's before/after samples
  and live readiness are a test oracle, not an arbitrary-process algorithm.
  Actual PID reuse was neither exercised nor forced. Permissions/namespaces and
  syscall availability must refuse safely; no privilege assumption is justified.
- **Historical membership is the missing information.** D1 deliberately reports
  its child before detaching/root exit. That oracle knowledge is not obtainable
  from a later pane-root snapshot alone. Root/tree/TTY/PGID labels and late
  migration do not recover all historical descendants. Pre-execution containment
  remains a candidate category, not disproven by this fixture; exact membership,
  unrelated migration exclusion and all native births/respawns still need proof.
  Literal interactive-shell `disown` and enforcement against escape are untested.
- **Native queue exclusion is local, not a process transaction.** The inspected
  queue/server sources support fixed non-WAIT segment reasoning; `run-shell`
  returns WAIT for its queue, not a global mutex. Q1's ready/release barriers and
  E1's same-client sequence are meaningful counterexamples, not stress proof.
  The diagnostic epoch stamp is not a unique production epoch allocator. No full
  server-generation/owner-incarnation/context/terminal/anchor/group/window/pane/
  shape/epoch/root-start/copied-consent conjunction spans irreversible effects.
- **Attachment and final-group guards remain separate.** Prior A05/A08/A10/A11
  records/code support fallback, missing-anchor and generation counterexamples,
  not a complete joint canonical-anchor/presentation/group guard at creation and
  actual attachment. Earlier F-series observations are group-fence subsets only.
  Whole-workload exit and final disappearance of the exact group/presentations
  are distinct required postconditions. An unconsented arrival must survive even
  if it prevents group disappearance; never sweep it into old consent.
- **Counts and unknown outcomes are represented honestly.** Independently parsed
  retained then-current JSON: one final run, six subsets, four failed properties and
  two narrow oracle passes. X1 witnesses effect-before-ack through a synthetic
  inherited pidfd; it does not test durable pending state or no-retry enforcement.
  Missing timeout/malformed/crash schedules and full attachment/stop recipes are
  explicitly untested/blocked. Earlier runs are not added to those counts.
- **Retrieval provenance is appropriately limited.** The recorded Linux HTTP 429
  failures and guessed root `systemd.c` HTTP 404 are disclosed, not turned into
  absence/impossibility evidence. I verified the corrected pinned
  `compat/systemd.c` retrieval and hash, not the historical HTTP attempts or
  supervisor approvals. No source-qualified `cgroup.kill` claim should be added.

## Initial checks and remaining decision (historical)

Executed lightweight checks only: `gh issue view` for the named tickets;
read-only pinned `gh api` source retrieval/hash comparisons; Python AST parse;
JSON parsing/count checks; probe/tmux SHA-256 checks; local manual hash/field
checks; `readelf -d/-Ws`; `pacman -Q tmux python glibc man-pages`; `uname -srmo`;
`git diff --check` and owned-file whitespace validation. These passed. No staged
files. `HEAVY_HELD` and `HEAVY_SLOT` were unset; no heavy job was run.

Initial lookup of the incorrectly assumed root `probes/exact-workload-helper`
returned `[fd error]: Search path '.../probes/exact-workload-helper' is not a
directory.` That lookup stopped and was reported; the assigned report supplied
the correct `docs/research/probes/exact-workload-helper` path. No runtime failure
was hidden behind an alternate probe execution mode.

No production implementation suite, Neovim/PTY release matrix, privileged work,
cgroup/systemd mutation, tracing, broad enumeration/signals or live-server access
was performed. Python syntax/JSON/whitespace checks cannot establish kernel
containment or native race safety. At this initial checkpoint, runtime evidence
remained writer-attested.

**Next action:** retain the blocking safety gates and present a new live
support/dependency/constraint decision. An explicitly authorized investigation of
stock tmux's optional systemd path is reasonable; adopting systemd, a termination
helper architecture, wrappers, resident observers, patches, privileges or weaker
consent is not. The launch-only decision grants none of those changes.

Trust boundary: backend identities, paths, process membership and native mutations
remain untrusted/fallible. At the initial checkpoint this reviewer executed no
probe effects, evaluated no fetched code, exposed no user environment/pane data
and changed only this review. The original probe's private routing and synthetic
pidfds did not cure its exceptional-path cleanup defect. Publication and
corrective writer/rerun authority remained with the parent.

## Corrective recheck — 2026-10-27 02:42 UTC

**Approved for publication as negative/inconclusive research evidence. No current
review blocker remains.** Reread the worktree skill first; verified the same
worktree, branch and baseline. Writer changes were complete; only this review was
edited. Reread the corrected report and all six probe-directory assets before
execution. The original review did not execute a probe; the following are new,
independent runs, not retroactive claims about that checkpoint.

### Corrections and execution safety

- **Cleanup finding corrected:** `probe.py:89–97,112–173,201–294` now owns a
  foreground `tmux -D` direct child, acquires its unreaped-child pidfd, confirms
  the private endpoint's PID and waits for an inherited-pidfd watchdog's ready
  marker before workload creation. SIGCHLD must be default; no custom reaper or
  thread is installed. The watchdog bounds server lifetime after installation
  with a 45-second wait and signals only the held server identity. Fixture alarms
  remain 30 seconds, including the detached child; barrier lifetime is bounded.
- Setup exceptions explicitly call cleanup. Per-resource teardown attempts
  continue after earlier errors; direct children are waited/reaped, fixture exits
  are observed through held pidfds, and directory removal requires known exits
  and no pending births. Ambiguity preserves evidence and does not cancel a
  still-needed watchdog. Before pidfd/watchdog acquisition, ordinary setup
  exceptions can still stop the positively owned direct child. This establishes
  sufficient ownership/bounds for these two authorized reruns, not arbitrary
  harness hard-kill safety or a product supervisor design.
- **Both low findings corrected:** the report now uses named ticket/map links;
  lines 93–95 identify three processes from two workloads. No number-only issue
  references remain in the corrected report. Current source excerpts also
  include the previously reviewer-checked starttime field.

### Actual independent commands and observations

Ran these exact payload commands sequentially, with `umask 077` and exclusive
`mktemp` output files; neither original evidence file was overwritten:

```sh
python3 docs/research/probes/exact-workload-helper/probe.py > /tmp/sess-exact-independent-observed.6Uk9Ir
python3 docs/research/probes/exact-workload-helper/probe.py --cleanup-faults > /tmp/sess-exact-independent-cleanup.jbXqMk
```

- Main: **one run, exit 0; six subsets: four failed safety properties, two narrow
  oracle passes**. Results and structured cleanup exactly match the corrected
  writer record. D1/C1/E1/Q1 remain counterexamples, not product passes.
- Fault checks: **one separate run, exit 0; two harness-control passes**.
  F1 injects setup failure after session creation and verifies cleanup from
  `__enter__`. F2 injects the first client's drain error; that error surfaces,
  its wait still runs, and second-client/server/watchdog cleanup continues.
  Results exactly match `cleanup_fault_checks`; these are not two additional
  termination-safety passes. The script's fixed output scope says “writer-run”;
  independent provenance is these reviewer invocations, not that literal label.
- For main, F1 and F2, cleanup reports server exit verified, watchdog exit 0,
  tracked fixture handles closed, direct clients reaped, no pending births and
  private directory removed afterward. Both retained output files are owned,
  regular mode-0600 files. Their SHA-256 values, respectively, are
  `3b46c92a1db15a6cbc266efc018be1811a8d4ff39bbda81299b8c37aa923a349`
  and `80890b1b545d1427672a094d683ecba42a08c7388e397273906e7c7af705c7f6`.

### Provenance, validation and limits

Current probe SHA-256 is
`9050b2bd0499f36944fcb0889c8d66e2e4bf27b198e584405b59aaef03267282`,
matching `runtime.json` and `observed.json`. Rechecked installed tmux hash and all
seven uncompressed local manual hashes. Independently retrieved/hash-matched
`client.c`, `tmux.c`, `tmux.1` and `server.c` at the original tmux pin; inspected
the foreground/no-fork sections cited in `sources.json`. Together with the six
sources checked initially, this covers nine distinct manifest inputs. The three
not independently retrieved are `cmd-if-shell.c`, `server-fn.c` and `window.c`.
No upstream manual archive, Linux cgroup source, successful-manager experiment or
prior native-safety runtime was newly inspected/executed. Earlier hash checks
and source inspection are not misrepresented as new retrievals.

AST parse, four JSON parses, hash/count/output comparisons, named-link check,
`python3 -m json.tool` for both outputs, `git diff --check` and owned-file
whitespace/newline checks passed. No staged files; inherited HEAVY admission was
unset, and no heavy or production application suite was needed/run. Both runtime
commands succeeded. Initial whitespace validation stopped on a new blank line
at review EOF (no-index status 3); the parent approved its precise correction,
and the same validator then passed. No runtime fallback was used. Writer
metadata's pending-review and unchanged-review fingerprint describe its
collection-time checkpoint; this section supersedes those status descriptions,
not their historical provenance.

Still untested: watchdog-expiry kill, harness hard-kill (especially before guard
installation), forced signal/server-wait failures, every setup boundary and the
retained-evidence ambiguity branch. These bounds/controls are sufficient for the
observed research run, not universal failure-safe cleanup. No broad enumeration
or signals, default tmux socket, live user jobs, direct cgroup/systemd calls,
ptrace or privilege/policy changes were used; native tmux's compiled optional
behavior was unchanged. Private routing is not protection against hostile
same-UID/root code. Only synthetic owned handles/direct children were signalled.

The substantive conclusion is unchanged: optional stock systemd placement is
promising but unqualified; absent separation here does not diagnose a configured
manager's behavior. pidfd acquisition, historical descendant containment, native
epoch/consent coordination, joint attachment guards and exact final-group
postconditions remain separate missing obligations. No universal impossibility
or adoption follows. Publish only with those limits, retain the blocking safety
gates, and seek a new live support/dependency/constraint decision. Parent retains
all publication/tracker and follow-up authority.
