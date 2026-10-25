# Native tmux identity and attachment safety — qualification evidence

**Outcome: NOT QUALIFIED; implementation handoff remains blocked.** Research only,
not a Sess implementation or an approved external-attachment recipe.

- Question: [#33](https://github.com/NnoFLy/sess.nvim/issues/33).
- Controlling decisions: [#32 acceptance](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573),
  [#30 persistence/identity/fencing](https://github.com/NnoFLy/sess.nvim/issues/30#issuecomment-6387360218),
  [#31 external attachment](https://github.com/NnoFLy/sess.nvim/issues/31#issuecomment-6391314744).
  Read through `gh issue view` / `gh api`; these are contracts, not executable inputs.
- Evidence collected **2026-10-25 UTC**; branch
  `research/persistent-terminal-native-safety`, base `eee53cca450a1e1a64e47ebe43f507fe85669dd0`.
  The publication report supplies the immutable evidence commit/asset URL (a file
  cannot embed its own Git commit hash). No PR, merge, tracker update, or plugin edit.
- Reproducer: [probe.py](probes/native-safety/probe.py).
  Historical full run: [observed.json](probes/native-safety/observed.json).
  Corrected P-series-only run: [correction-observed.json](probes/native-safety/correction-observed.json);
  independent regression controls: [correction-controls.json](probes/native-safety/correction-controls.json).
  `pass` below always means **only the stated tested subcase**, not the complete gate.
  This correction did not rerun A/S/F cases or qualify any full gate.

## Findings that prevent handoff

1. **`kill-window` is not verified workload termination.** A synthetic Python root
   ignoring SIGHUP survives removal of its exact window/pane, with the same Linux
   PID/starttime. Command status is 0. A 300 ms bounded post-removal observation
   still finds it running; only probe cleanup explicitly SIGKILLs that identity.
   Source closes the PTY; it neither conditionally signals the exact root using a
   Linux lifetime handle nor waits for verified termination. Normal SIGHUP-sensitive
   roots do die. Removing a window/group is therefore not sufficient stop success.
2. **`pane-created` is not an inline epoch fence.** tmux 3.8 has this hook for both
   creation and respawn, but its hook commands enter the global queue. Within the
   client queue, `respawn-pane -k` followed by a format read sees the **old stamp**,
   while window/pane IDs remain unchanged and PID changes. A subsequent invocation
   sees the new stamp. Creation `-P -F` output likewise precedes stamping. An ordinary
   query/stop pair cannot fill this gap. PID comparison rejects the tested respawn,
   but neither establishes a Linux start identity nor proves PID-reuse safety.
3. **No qualified native start-identity check-and-stop primitive was found.** The
   pinned format table exposes `pane_pid`, not Linux `/proc/PID/stat` starttime or a
   pidfd. The proposed `#{pane_start_identity}` expands empty. `start_time` is server
   start time; OSC 133 command times are not process start identity. Invoking a shell
   to read `/proc` yields to competing tmux mutations and is not the required native
   boundary. Source plus probes establish a useful non-yielding *format/queue*
   segment, not the complete consent identity/termination contract.
4. **The attachment candidate is only partially qualified.** Exact-ID and nonempty
   expected generation/owner/incarnation/context/role checks reject the tested stale
   targets, including actual ID reuse across server replacement. Presentation-only
   checks still accept after the canonical anchor is deleted while the presentation
   survives. A complete joint anchor/presentation/group/window guard, all controlled
   hooks, and all mutation/crash cases remain unqualified. Do not distribute this
   probe's simplified guard as the complete external recipe.

A human decision is needed on the missing native identity/epoch/termination
mechanisms, or further evidence of a sufficient primitive, before implementation
handoff. This report does **not** authorize weaker consent, query-then-kill,
changing backends, a required external-client helper, or any implementation.

## Exact runtime and storage assumptions

| Item | Observed provenance |
| --- | --- |
| Kernel/architecture | `Linux 7.2.10-arch1-1 x86_64 GNU/Linux` |
| tmux executable | `/usr/sbin/tmux` (`/usr/bin/tmux`), `tmux 3.8`, Arch package `tmux 3.8-1` |
| Executable SHA-256 | `f4d25f698c2eae25b742ad8a6d4cb8c7c5309a6ebf586e4e541fc9655de10660` |
| Installed package provenance | Cached `tmux-3.8-1-x86_64.pkg.tar.zst`; SHA-256 `458fb70e06289bb30e90da74f4724ee87dd92ea7dd6a0bdbf4c7c6adcec75a02`; archive `usr/bin/tmux` has the same executable hash |
| Build metadata | `.BUILDINFO`: builddate `1791450958`, devtools `1:1.5.2-1-any`, PKGBUILD SHA-256 `b51da8bc9578018f71bcd59ea1704c48c188615eb4ee3c6700624c2e6cd72c94`; package build time 2026-10-08 |
| Runtime libraries | `libevent 2.1.13-2`, `ncurses 6.6-2`, `glibc 2.44+r50+g1848099f063e-1` |
| Harness | `/usr/sbin/python3`, Python `3.14.8-1` package; `/bin/sh` resolves to `/usr/bin/bash`, `bash 5.3.20-1` |
| Official stable Neovim | `gh api repos/neovim/neovim/releases/latest` resolved `v0.12.6`, published 2026-10-09; annotated tag peeled to `779c36969e31080503be2dfccbcc3f999e289606` |
| Available Neovim | `/usr/bin/nvim` is installed stable `NVIM v0.12.6` (confirmed during correction). PATH selects `/home/nnofly/.local/bin/nvim`, `NVIM v0.13.0-dev-d714648-dirty`; previously recorded dev SHA-256 `557198ff1a62ba5c1d5dc6682f230ba600c83971a17eb5b150e0a7e1b5bce93f` |
| Stable Neovim gate | **untested**, not unavailable: no stable Neovim scenario was exercised. These are native tmux probes, not a supported Neovim/tmux tuple pass |
| Worktree and disposable storage | `/tmp` is `tmpfs`, `rw,nosuid,nodev,nr_inodes=1048576,inode64,huge=advise,usrquota`; executable filesystem is local btrfs, `rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2` |

No durability conclusion follows from tmpfs tests. No file/directory fsync,
power-loss, storage recovery, or network filesystem qualification belongs to this
lane. Binary/package identity is recorded, not a claim of a reproducible rebuild
or verification of every downstream Arch patch against upstream.

## Pinned primary sources and reasoning

Official tmux **3.8** annotated tag `72c20dc22c24c34b8e39506f524c9c88da2f48aa`
peels to **`7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`**. All tmux links below use
that exact commit. Sources were fetched read-only to a private temporary directory:

```sh
rev=7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53
# Substitute a file named in the table below; output is source text, not commands.
gh api "repos/tmux/tmux/contents/cmd-if-shell.c?ref=$rev" \
  -H 'Accept: application/vnd.github.raw+json'
gh api repos/tmux/tmux/git/ref/tags/3.8
gh api repos/tmux/tmux/git/tags/72c20dc22c24c34b8e39506f524c9c88da2f48aa
```

| Source | What it establishes (not a runtime gate pass) |
| --- | --- |
| [Manual](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L8756-L8796) | `if-shell -F` evaluates a format synchronously; this differs from asynchronous shell execution. Manual also documents hooks/formats/groups; no process-start-aware conditional kill is promised. |
| [cmd-if-shell.c:38–116](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-if-shell.c#L38-L116) | Target has `CMD_FIND_CANFAIL`; `-F` expands once, chooses typed commands, inserts them immediately after this item, returns NORMAL. Without `-F`, shell work can WAIT. |
| [cmd-queue.c:704–784](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-queue.c#L704-L784), [server.c:266–284](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L266-L284) | `cmdq_next` drains a queue until empty or WAIT; server drains global and then client queues. No competing ordinary client mutation between fixed `if -F` and immediately inserted non-WAIT `kill-window`/`new-session`/`attach-session`. This is not a filesystem transaction or exclusion of independent OS process exit. |
| [cmd-find.c:1235–1264](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-find.c#L1235-L1264), [format.c:6917–6974](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/format.c#L6917-L6974) | Failed CANFAIL target is not proof of refusal; format defaults can use another context. Actual exact session ID is mandatory, not just markers. Runtime A05 supplies a real fallback client. |
| [spawn.c:75–111](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L75-L111), [spawn.c:587–595](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L587-L595), [hooks.c:60–77](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/hooks.c#L60-L77), [hooks.c:230–249](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/hooks.c#L230-L249) | `pane-created` carries pane/respawn information, but has no `_cmdq_item`; hooks append globally. It is not an inline client-queue epoch assignment. S01/S02 reproduce that ordering without sleeps. |
| [cmd-kill-window.c:61–90](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-kill-window.c#L61-L90), [window.c:1568–1600](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/window.c#L1568-L1600) | Unlink/destroy the exact window and close PTY; no verified root/descendant termination. Success does not mean the PID/start identity exited. |
| [server-fn.c:239–263](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server-fn.c#L239-L263), [server-fn.c:440–454](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server-fn.c#L440-L454) | Last-window detach destroys the exact session group, including grouped presentations. New-window against old exact IDs then fails; a preexisting arrival prevents emptiness. This mechanism does not stop a HUP-ignoring orphan. |
| [cmd-new-session.c:142–164](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-new-session.c#L142-L164), [cmd-new-session.c:305–326](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-new-session.c#L305-L326) | Missing target may become a new group. Grouped creation spawns an initial window before group synchronization. A08 is an intentionally unsafe negative control; A01 checks retained window identity, not every transient process. |
| [cmd-attach-session.c:72–100](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-attach-session.c#L72-L100) | Attach resolves its target again; guard must cover exact presentation and authoritative anchor/group, on the current generation. |
| [format.c:2578–2587](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/format.c#L2578-L2587), [format table](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/format.c#L3830-L4210) | `pane_pid` is tmux's stored PID while fd exists; no process-starttime/pidfd format. `window_linked_sessions` counts groups plus ungrouped sessions; the corresponding list contains names, not exact IDs. Names are not used as ownership proof in this probe. |
| [cmd-rename-window.c:52–66](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-rename-window.c#L52-L66), [format.c:6758–6798](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/format.c#L6758-L6798) | Rename input is a format even through argv. `#()` is a format job facility; untrusted values must not be recursively evaluated. P01b proves raw argv is insufficient; fixed lookups do not recursively evaluate their returned option data. |

Linux process observation uses a bounded 4096-byte read of `/proc/PID/stat`,
field 22 (starttime), excluding zombie state. ABI reference: pinned Linux v6.12
[`fs/proc/array.c:585–612`](https://github.com/torvalds/linux/blob/adc218676eef25575469234709c2d87185ca223a/fs/proc/array.c#L585-L612).
This reference documents the field; it is not a claim that the running 7.2.10
kernel was built from v6.12. The probe's starttime observation occurs **outside**
tmux and is only an oracle, not a qualified native destructive primitive.
Official stable Neovim source pin:
[`779c36969e31080503be2dfccbcc3f999e289606`](https://github.com/neovim/neovim/tree/779c36969e31080503be2dfccbcc3f999e289606).

## Disposable setup, command boundary, and cleanup

Run from the exclusive worktree, with existing Python/tmux; install nothing:

```sh
# Focused correction only; omit --parser-only solely to reproduce the historical full probe.
# Use an exclusive private output file; do not overwrite the historical observed.json.
umask 077
output=$(mktemp /tmp/native-safety-correction.XXXXXX)
python3 docs/research/probes/native-safety/probe.py --parser-only > "$output"
python3 -m json.tool "$output" >/dev/null
rm -- "$output"
python3 - <<'PY'
import ast
from pathlib import Path
ast.parse(Path('docs/research/probes/native-safety/probe.py').read_text())
PY
```

The script creates mode-0700 `TemporaryDirectory` roots, private HOME, config,
fixture storage, and short absolute Unix sockets. No inherited TMUX, user config,
environment values, credentials, real workloads, or pane captures are used. Only
PATH/HOME/TERM/XDG_CONFIG_HOME/SHELL/LC_ALL are constructed; environment values are
not recorded. Initial startup explicitly uses `-S PRIVATE -f PRIVATE_CONFIG`;
**every later backend command uses `-N -S PRIVATE`**. `tmux -V` is only a version
query. No command selects the default/user server.

Controlled config: `exit-empty off`, `exit-unattached off`,
`destroy-unattached off`, `/bin/sh` default shell, status off, synthetic server
`@generation G1`. Owner markers are synthetic `O1/I1/C1/anchor`; grouped
presentations get separate `presentation` markers. These names are fixtures,
not a proposed production protocol. System configuration isolation is not
qualified here (belongs to #34); no claim that `-f` alone proves it is made.

Backend calls are argv-based, five-second bounded. P03 uses `raw=True` to
capture bytes without newline normalization; other calls still use text mode and
do not establish malformed-byte transport safety. P03's synthetic byte emitter
uses the same private HOME/environment and five-second bound. Reads of `/proc` and PTY output
are bounded (4096/8192 bytes); PTY bytes are discarded, only byte count recorded.
Synthetic fixture roots do no real work. Ordinary fixtures accept SIGHUP; the
negative fixture installs `SIG_IGN` before touching its ready file. Setup waits
for that explicit ready file, not a timing guess.

Cleanup kills **only the private test server**, then any tracked synthetic roots
still matching PID/starttime, reaps owned PTY clients, asserts those identities
are no longer live, and removes its temporary root. The ignored-HUP root is
explicitly SIGKILLed by this cleanup; that is not offered as a product stop
implementation. An additional independent private test server acts as an
unrelated-server sentinel. No broad server/group kill is a candidate operation;
`kill-server` and `kill-session` appear only in disposable setup/cleanup or
explicit adversarial deletion/replacement controls.

## Expected versus observed subcases

The **historical** JSON contains **31** executable subcases with recorded labels
**24 pass, 6 fail, 1 blocked**; its P03/P05 labels do not prove the broader coverage
previously claimed. P03 tested synthetic strings only; P05 tested literal
backslash text and coupled target/generation, masking empty-target fallback.
The corrected run contains **7 P-series subcases: 6 pass, 1 fail** (the intentional
raw-rename negative control). It is not a new 31-case run or a full gate pass.
The table retains historical A/S/F observations and uses the correction for P rows.
Failures include intentionally unsafe negative controls; exit 0 from the harness
means it detected its expected observations, **not** that native safety passed.
IDs below are local evidence case IDs, cross-referenced to #32 conditional
native targeting, guarded attachment, and injection acceptance rows.

| Cases | Expected oracle / observed result | Outcome |
| --- | --- | --- |
| A01 | Guarded grouped creation yields exactly one `PRESENT=$digits` line; anchor/presentation window, pane, root PID match; one retained window. Accepted transient startup shell is not measured. | **pass**, retained-identity subset |
| A02–A03 | Real ordinary PTY attaches to exact presentation; after generation change a second attempt creates no extra attached client. First client remains. 680 synthetic bytes discarded. | **pass**, simplified marker/ID guard only |
| A04 | Independently empty generation/owner/incarnation/context/role refuses creation; all five print `REJECT`, **exit 0**. Rejection output cannot be accepted as success. | **pass** |
| A05 | With a real attached fallback client, missing `$999999` plus marker-only guard prints `ACCEPT`; exact-ID guard prints `REJECT`. Without a client the false positive did not reproduce. | **pass**, detects unsafe negative control |
| A06–A07 | Anchor rename preserves exact-ID access; changed owner marker refuses. | **pass** |
| A08 | Unguarded `new-session -t` after exact anchor deletion creates another group. This is the prohibited preliminary-query recipe's counterexample, not an approved operation. | **fail**, negative control |
| A09 | Fixed exact-ID/marker guard after anchor disappearance refuses without creating another group. | **pass** |
| A10 | Kill disposable server, initialize replacement, deliberately reuse `$0` and owner markers but set new generation. Old generation refuses creation **and actual PTY attachment**. | **pass**, deterministic cross-invocation boundary |
| A11 | Delete canonical anchor only; presentation survives. A presentation-only exact-ID/marker guard still accepts. | **fail**, negative control; complete joint guard unqualified |
| S01 | `pane-created` stamp changes on respawn, but same-client-queue read still has old stamp with new root PID and unchanged pane/window IDs. Next invocation sees changed stamp. | **fail**, inline epoch assumption |
| S02 | Creation `-P -F` returns empty epoch before hook; later observation gets stamp. Unstamped panes must not be admitted; delayed admission alone does not prove replacement safety. | **fail**, inline admission assumption |
| S03 | Respawn old consent carries old PID; fixed guard refuses kill and replacement root survives. | **pass**, no actual PID reuse |
| S04 | Exact window/pane/PID and one-pane format guard stops normal fixture; pane gone and original PID/starttime no longer running. | **pass**, no native starttime revalidation |
| S05 | Same native window removal with ignored SIGHUP returns 0, pane gone, exact root PID/starttime remains running. | **fail**, required termination property |
| S06 | Native split creates unsupported two-pane shape. One-pane guard refuses, original root survives. | **pass** |
| S07 | Link owned window into unrelated synthetic session; distinct-link-group-count check refuses, root survives. Does not constitute complete group-shape validation. | **pass**, cross-group-link subset |
| S08 | Proposed native start-identity format is empty; pinned format table supplies no Linux starttime/pidfd conditional primitive. | **blocked**, no sufficient primitive qualified |
| F01 | Removing last window destroys anchor and presentation; later native `new-window` targeting old exact presentation ID fails. | **pass**, group existence fence only |
| F02 | Create unconsented native arrival first, then remove old window; new root and owner group survive. | **pass** |
| F03 | Competing native marker-clear vs guarded kill: 40 runs, 10 stop-first / 30 mutation-first. Rejection preserves fixture; no guard-accepted replacement. | **pass**, source-backed non-WAIT segment subset |
| F04 | Competing last-window kill vs native new-window on presentation: 20 runs, 9 stop-first (arrival errors) / 11 arrival-first (new root/group survive). | **pass**, group fence subset |
| F05 | Stop on one private server leaves second private server's exact sentinel PID/starttime alive. | **pass** |
| P01 | Untrusted option value includes `#()`, format text, semicolon, quotes, slash; fixed lookup returns data, fixed comparison rejects. No synthetic injection file appears. | **pass**, no recursive expansion |
| P01b | Raw rename argv containing `#{session_id}` expands to `$0`; argv/shell quoting alone does not preserve data. `#()` execution is not established by this short-lived client. | **fail**, negative control |
| P01c | Doubling `#` before rename preserves format metacharacters, no injection file. tmux escapes literal backslash in stored label. | **pass**, bounded fixture only |
| P02 | Unknown command parse fails with status 1. | **pass**, parser subset |
| P03 | Byte oracle rejects eight synthetic malformed records, accepts exact LF. Three synthetic subprocess emissions preserve exact LF/CRLF/embedded-CR bytes; only LF accepts. Three real tmux outputs accept LF and reject underscore-sanitized attempted CR; they do **not** exercise tmux-origin CR. A text-mode emitter read wrongly accepts normalized CRLF. | **pass**, byte-oracle subset; real tmux CR/external-consumer handling untested |
| P04 | Whole-input unknown-command parse error applies no earlier assignment. A later runtime target error retains an earlier assignment. Both exit 1. No rollback claim. | **pass** |
| P05 | Eight inputs (including actual newline U+000A and ESC U+001B) rejected independently in target and generation: **16 field/input checks**. Empty target is no longer defaulted to anchor; omitted/explicit-valid and alternate-valid controls succeed. | **pass**, probe construction only, before backend invocation |

The hook stamp is deliberately a diagnostic `pane-id + created_respawn` value,
**not** a collision-free production epoch allocator. It distinguishes first
creation from first respawn to expose ordering; no persistent identity scheme
has been implemented. Linux process identities are recorded only transiently;
JSON contains booleans/counts, no PID, process text, paths, environment, or screen.

## Race/crash coverage and remaining required cases

There are no sleeps between a native format check and its operation. The
respawn/creation failures use deterministic same-client queue ordering. Server
replacement and last-window disappearance have explicit sequential boundaries.
F03/F04 add concurrent other-client queues; counts are recorded, but scheduling
luck is **not** the atomicity argument. The source's queue-drain behavior is.
Polling sleeps only observe readiness or postconditions, never prove exclusion.

| Required remainder | Outcome / why it is not a pass |
| --- | --- |
| Full generation + exact anchor + owner incarnation + group/window/pane shape + terminal/workload epoch + PID/start identity in one native destructive boundary | **blocked** by S01/S05/S08; individual format checks are not the full conjunction. No process-observation helper or tmux patch introduced. |
| Complete joint presentation/anchor guard and exact window membership at create and attach; canonical marker removal while presentation persists | **untested** as a complete recipe; A11 proves simplified presentation-only checks insufficient. |
| Competing native create/rename/exit/respawn/replace/marker removal/group deletion and all controlled hook orderings at each boundary | **untested** beyond the specific deterministic and repeated cases above. No arbitrary raw custom-hook safety claim. |
| Forced PID reuse, same-server window/pane numeric-ID wrap/reuse, natural/signaled exit races, root/descendant escape, pane moves/swaps, contradictory terminal stamps | **untested**. Respawn does preserve pane/window IDs and replacement server reuses session ID, but these are not actual Linux PID reuse. |
| Crash after guard/before operation; crash after effect/before output; malformed backend bytes integrated with real external consumer; client crash during presentation acquisition | **untested**. Runtime/parse partial effects are measured, not a durable crash-reconciliation protocol. |
| Accepted transient grouped shell lifetime/termination and disposable presentation cleanup; no extra retained process | **untested** beyond retained window/pane/root equality. No claim all transient shell side effects or orphaning were measured. |
| All hostile cwd/labels/IDs/control characters through every creation/management/copied-instruction surface | **untested** beyond fixed lookup, rename, constrained tokens and output-oracle fixtures. No public API/UI adapter exists in this lane. |
| Latest-stable Neovim plus two ordinary concurrent writable PTYs / release qualification | **untested** despite installed `/usr/bin/nvim` v0.12.6; native one-PTY guard checks do not substitute for #34/#36 or the full release matrix. |
| File/directory durability, storage errors, owner journal/tombstone/recovery | **untested**, other lane; tmpfs cannot establish power-loss durability. |

The bounded question has a negative/incomplete answer: native non-yielding
format branching and last-window group fencing have useful source/runtime
evidence, but the required complete native exact-stop/epoch/termination gate is
not met. Preserve this incompatibility as blocking in acceptance review. No issue
was closed/commented, no map edited, and no unsupported primitive was repaired.

## Validation and evidence interpretation

### Audit correction and independent controls

The historical JSON is preserved, not silently rewritten as a rerun. Its P03/P05
coverage is superseded by the focused correction JSON. That record includes
fixture-only output hex (not real environment or pane contents), all 16 named
P05 rejections, and positive controls rather than just a reported total.

Two independent in-memory regressions were also run via `runpy.run_path` and the
P-series function, each with its own disposable server (no source mutation):

1. Wrap `Server.guard` to pass `target=target or self.anchor` to the corrected
   method. The independent empty-target check fails with
   `accepted invalid target:empty` while generation remains valid.
2. Wrap `check_output` to replace `b"\r\n"` with `b"\n"` before validation.
   The P03 malformed-byte assertion fails, detecting CRLF normalization.

Both expected assertion failures are retained in `correction-controls.json`.
Separately, P03 actually reads the synthetic CRLF emitter with `text=True` and
confirms the resulting false acceptance. These are oracle negative controls,
not failed plugin tests or new safety gate passes.

The first corrected probe attempt failed because real tmux `display-message`
converted attempted CR bytes to underscore. A bounded private `show`/`display`
check confirmed the same conversion. The final oracle records the transformation
instead of asserting CR arrived from tmux; real tmux-origin CR remains untested.
Synthetic emitter CR preservation/rejection does not fill that gap or qualify an
external consumer. Stable Neovim availability was checked with explicit
`/usr/bin/nvim --version`; only its version was exercised, not a session scenario.
No A/S/F race counts, source-backed negative findings, or incomplete
anchor/termination conclusions were promoted by this correction.

- The historical full harness and corrected `--parser-only` command exit **0**
  when their expected observations occur. The focused JSON retains P01b's failed
  safety property; it contains no A/S/F rerun or complete qualification.
- Python AST parse and `python3 -m json.tool` validate assets without dependencies.
- `git diff --check` checks the research-only diff before publication.
- No Lua added/changed: StyLua is not applicable. No plugin implementation changed:
  `sh tests/run.sh` was not used as a substitute for native qualification.
- Initial exploratory assertion failures exposed needed corrections to the probe:
  fallback needs a real attached client; hook assignment needs `set-option -F`;
  native rename expands formats and escapes backslashes. Final evidence reflects
  those observations rather than counting the earlier assumptions as passes.
- A source lookup for nonexistent `notify.c` returned 404; the actual 3.8 event
  path is `events.c`/`hooks.c`. This was a source-navigation correction, not an
  infrastructure failure. No agent runtime/tool setup failure occurred.
