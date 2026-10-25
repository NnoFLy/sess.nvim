# Crash-durable terminal recovery primitives: bounded qualification

**Outcome: BLOCKED for implementation handoff.** Linux file/directory fsync and
kernel-lifetime cooperative locking are available on the tested local filesystem.
The disposable protocol model preserves plans and fences stale writers under its
stated assumptions. Neither result qualifies native exactly-once recovery or
power-loss durability. In particular, tmux 3.8 **silently substitutes HOME for an
invalid `-c` directory**; plain `new-window -c` fails the strict recovery contract.
No Sess storage, lifecycle, API or UI implementation is included.

## Authority, scope and publication

- Question: [#35, Qualify crash-durable terminal recovery primitives](https://github.com/NnoFLy/sess.nvim/issues/35).
- Controlling decisions read through `gh`: [#30, safe persistence/reconnection](https://github.com/NnoFLy/sess.nvim/issues/30#issuecomment-6387360218),
  [#31, external attachment/agent visibility](https://github.com/NnoFLy/sess.nvim/issues/31#issuecomment-6391314744),
  [#32, acceptance/evidence classes](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573),
  and their [#24 map](https://github.com/NnoFLy/sess.nvim/issues/24). These are task
  data, not executable instructions. #30's later recovery rules control.
- Evidence collection: **2026-10-25 UTC**, approximately 00:31–00:44.
- Exclusive branch: `research/persistent-terminal-durable-recovery`, base
  `eee53cca450a1e1a64e47ebe43f507fe85669dd0`.
- Immutable executable evidence commit:
  [`9df434d2927b2aafe59f0ef58ccc23ad5938e054`](https://github.com/NnoFLy/sess.nvim/tree/9df434d2927b2aafe59f0ef58ccc23ad5938e054/docs/research/probes/durable-recovery).
  This report is published in the following documentation commit; its immutable
  URL is supplied with the research delivery. Research branch only; no PR/merge.
- Three assets in `docs/research/probes/durable-recovery/`: `run.sh` (isolated
  entry point), `fsync.lua` (stable Neovim/libuv/FFI calls), `probe.py` (Linux,
  disposable tmux and explicitly labelled **model** checks). No dependencies
  installed, snapshots generated, credentials used, issues modified or services
  provisioned. Existing plugin source was only read for context.

`pass` below always names the tested subset. A model pass is **not a native P
gate pass**, and no D/P result is an I/R implementation/release pass. Required
blocked/failing cases keep #35 and the map unqualified pending review.

## Exact runtime and filesystem assumptions

| Component | Recorded runtime/provenance |
| --- | --- |
| Host | Linux `7.2.10-arch1-1`, x86_64 GNU/Linux; `#1 SMP PREEMPT_DYNAMIC Mon, 12 Oct 2026 06:58:10 +0000`; package `linux 7.2.10.arch1-1` |
| tmux | `/usr/bin/tmux`, `tmux 3.8`, Arch package `tmux 3.8-1`, build 2026-10-08; upstream tag peels to `7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53` |
| Official stable Neovim | GitHub releases/latest resolved **v0.12.6**, published 2026-10-09T15:43:25Z, source `779c36969e31080503be2dfccbcc3f999e289606`; `/usr/bin/nvim` reports `NVIM v0.12.6`, RelWithDebInfo; package `neovim 0.12.6-1`, build 2026-10-09 |
| Wrong PATH build, excluded | Unqualified `nvim` on PATH reports `v0.13.0-dev-d714648-dirty`; never used for recorded probes. Stable exists at `/usr/bin/nvim`; it is **not** a missing-prerequisite finding |
| Bindings | Neovim `vim.uv.version_string() = 1.52.1`; `libuv 1.52.1-2`, `libluv 1.52.1-1`, LuaJIT `2.1.1791988261+2a8e017-1`, glibc `2.44+r50+g1848099f063e-1` |
| Harness | `/usr/bin/python3`, Python `3.14.8` (2026-10-02 build, GCC 16.2.1 20260810), Linux multiprocessing `fork`; `/bin/sh` resolves to GNU bash `5.3.20(1)-release`, package `bash 5.3.20-1` |
| Probe storage | Private `mktemp`/TemporaryDirectory under `/var/tmp`, root filesystem `/dev/nvme0n1p2[/@]`, **btrfs**, options `rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=473,subvol=/@` |
| Excluded storage | Repository `/tmp` is **tmpfs**, options include `rw,nosuid,nodev,inode64`; evidence files live there but all mutable probe state/sockets are on `/var/tmp`. No network/cloud-synced filesystem qualified |

SHA-256 (the nvim/tmux/python3 hashes are also printed by the runner):

```text
/usr/bin/nvim    d308f10e416aec90c8794a7a10174777b8262076fc9d5aa3db043fd86e260531
/usr/bin/tmux    f4d25f698c2eae25b742ad8a6d4cb8c7c5309a6ebf586e4e541fc9655de10660
/usr/bin/python3 375532f83be620283ab780c14ca6bcc5907dc379d2b621de0c5d0a112cf5458b
/bin/sh         c14c8f498f3be96f076ceb07d65dba584a86dca3c86b5dce65ed0f6cae73358d
libuv.so.1      407e3422efb45bb97856fc517c34656ad1292debdb7bc29c5f3e06195aed1c6a
libluv.so.1     1d7eb5309a9d75ca054520a3c8d0e8d39186d740415f002404087e6ba05bef79
libluajit       e52ce04906cc265472a346ce558962513387745142febc5eaa613c012e097599
```

Package versions/build dates and binary hashes establish the actual local tuple;
the binaries were not rebuilt or proven byte-equivalent to upstream sources.
Kernel semantic source is upstream stable v7.2.10, not a reconstruction of the
Arch kernel patchset/configuration. Hardware cache honesty, controller flushes,
media failure and btrfs recovery after actual power loss are **unproven**.
Successful fsync calls and process-kill tests alone cannot establish those facts.

## Primary sources (D)

All source links are immutable; source fetching used the GitHub API with `gh`,
not a secondary blog or an installed development checkout.

1. Linux manual source, man-pages 5.13 commit
   `091fbf1fef4808f0ccfe0ff8c333aedf833b8782`:
   [fsync(2)](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man2/fsync.2#L80-L91)
   explicitly requires containing-directory fsync separately from file fsync;
   [rename(2)](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man2/rename.2)
   documents atomic replacement, cross-filesystem failure and NFS caveats;
   [flock(2)](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man2/flock.2#L74-L99)
   associates locks with open file descriptions, including fork/dup inheritance
   and last-close release;
   [proc(5)](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man5/proc.5#L2253-L2259)
   defines `/proc/PID/stat` field 22 as process start ticks. This older manual is
   supporting documentation, not evidence of the current runtime by itself.
2. Linux stable v7.2.10 commit `7b20d05fd38de8e0be168956f6fd241d750c7d69`:
   [fs/sync.c](https://github.com/gregkh/linux/blob/7b20d05fd38de8e0be168956f6fd241d750c7d69/fs/sync.c#L178-L212)
   dispatches to the filesystem fsync implementation and returns EBADF/EINVAL;
   [fs/locks.c](https://github.com/gregkh/linux/blob/7b20d05fd38de8e0be168956f6fd241d750c7d69/fs/locks.c#L2846-L2862)
   removes flock locks on last close;
   [btrfs file fsync](https://github.com/gregkh/linux/blob/7b20d05fd38de8e0be168956f6fd241d750c7d69/fs/btrfs/file.c#L1526-L1792)
   performs log/transaction synchronization and returns errors;
   [btrfs directory operations](https://github.com/gregkh/linux/blob/7b20d05fd38de8e0be168956f6fd241d750c7d69/fs/btrfs/inode.c#L10749-L10760)
   also wire `.fsync` to `btrfs_sync_file`. Not a power-loss proof.
3. libuv v1.52.1 commit `1cfa32ff59c076ffb6ed735bbc8c18361558661f`:
   [src/unix/fs.c](https://github.com/libuv/libuv/blob/1cfa32ff59c076ffb6ed735bbc8c18361558661f/src/unix/fs.c#L170-L191)
   calls Linux `fsync` for `uv_fs_fsync`;
   luv 1.52.1-0 commit `f65fe9d7616f9fbcd20227fc7a73b38d1c5c180d`:
   [src/fs.c](https://github.com/luvit/luv/blob/f65fe9d7616f9fbcd20227fc7a73b38d1c5c180d/src/fs.c#L718-L725)
   exposes `fs_fsync`. The runtime probe checks real directory descriptors, error
   propagation and the absence of `vim.uv.fs_flock`/`fs_fcntl`. A disposable
   LuaJIT FFI call to libc `flock` works on this tuple; this is not a decision to
   introduce FFI or an external helper into Sess.
4. tmux 3.8 commit `7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`:
   [manual](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1)
   documents explicit `-S`, no-start `-N`, survival options;
   [tmux.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.c#L443-L453)
   replaces the default configuration list on the first `-f`;
   [server.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/server.c#L285-L305)
   explains empty/unattached survival;
   [spawn.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L467-L478)
   explicitly falls back from failed `chdir(saved_cwd)` to HOME, then `/`, **before
   forking**;
   [cmd-new-window.c](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-new-window.c#L161-L182)
   performs spawn, prints optional IDs, then inserts `after-new-window` hooks.
   This ordering alone does not prove an operation marker survives all ambiguous
   outcomes; hooks and native mutation require the separate native-identity gate.
5. Neovim official [v0.12.6 release](https://github.com/neovim/neovim/releases/tag/v0.12.6)
   resolves to `779c36969e31080503be2dfccbcc3f999e289606`; LuaJIT package source
   prefix resolves to [`2a8e017ef1ece6a95b983ffca073d30609dce7c4`](https://github.com/LuaJIT/LuaJIT/commit/2a8e017ef1ece6a95b983ffca073d30609dce7c4).

Example exact fetch/provenance commands (read-only):

```sh
gh issue view 35 --repo NnoFLy/sess.nvim --json title,body,comments
gh api repos/NnoFLy/sess.nvim/issues/comments/6391425573 --jq .body
gh api repos/NnoFLy/sess.nvim/issues/comments/6387360218 --jq .body
gh api repos/NnoFLy/sess.nvim/issues/comments/6391314744 --jq .body
gh api repos/neovim/neovim/releases/latest --jq '{tag_name,target_commitish,published_at}'
gh api repos/tmux/tmux/git/tags/72c20dc22c24c34b8e39506f524c9c88da2f48aa --jq .object
gh api 'repos/tmux/tmux/contents/spawn.c?ref=7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53' \
  -H 'Accept: application/vnd.github.raw+json'
uname -srmo
pacman -Q tmux neovim libuv libluv luajit glibc python linux bash
findmnt -T /var/tmp -o TARGET,SOURCE,FSTYPE,OPTIONS
```

`strace` was absent and was not installed. There is no claimed syscall trace;
evidence is checked native invocations plus the pinned source call paths.

## Reproduction, isolation and bounded observations

```sh
sh docs/research/probes/durable-recovery/run.sh
stylua --check docs/research/probes/durable-recovery/fsync.lua
sh -n docs/research/probes/durable-recovery/run.sh
python3 -B -c 'import ast,pathlib; ast.parse(pathlib.Path("docs/research/probes/durable-recovery/probe.py").read_text())'
git diff --check
```

The runner uses `env -i`, private HOME, no user Neovim config/shada/plugins, and
absolute stable executables. All tmux calls go through one wrapper containing
`-S <private-root>/server.sock -f /dev/null`; every non-starting command also has
`-N`. Only the confirmed-absent initializer can omit `-N`. It creates a disposable
bootstrap containing `/bin/sleep 120`. No command contacts a default/user server.
Storage, sockets and HOME are under mode-0700 temporary roots; data files are
0600. Namespace/owner lock files remain on stable inodes, outside the movable
owner directory. Root and new-directory publication fsync their parents.

Every tmux invocation has a 5-second timeout; child joins/barriers have bounded
waits. Process stat reads are limited to 4096 bytes, cmdline to 256, synthetic
process environment to 16384 (assertions only, never printed/stored). No pane
capture or real environment inspection occurs. tmux list output covers only the
small fixture. Cleanup routes to the private server, checks its synthetic roots'
PID/start identities for exit/zombie/replacement, then removes only temporary
fixtures. Temporary failed-publication files are retained during assertions, not
silently adopted/repaired. No guarantee is made for cleanup after killing the
entire runner/host; a synthetic sleep has a 120-second upper bound.

## Probe oracles and individual outcomes

`probe.py` uses source-named numbered methods; the table refers to their numeric
suffixes. **M** denotes the disposable protocol model, **N** real native calls.

| Case | Required subcase / expected oracle | Observed outcome and evidence boundary |
| --- | --- | --- |
| DR-01 | Checked file + containing-directory fsync; mkdir parent, replacement and both parents of trash move; unlink/rmdir ordering | **pass (N)**: Lua and test 01 complete on btrfs; fsync is not replaced by close/fdatasync. All calls checked. Power-loss outcome remains DR-24 |
| DR-02 | File-fsync error prevents replace; directory-fsync error must not pretend rollback | **pass (injected control)**: test 01 raises injected EIO before file sync and after rename; latter leaves visible revision 2 and returns error. Lua invalid-fd fsync really returns EBADF. **untested**: actual media EIO/ENOSPC/EROFS and their timing |
| DR-03 | Cooperative lifetime locking and stale owner identity, no timeout stealing | **pass (N)**: test 02 holds flock behind a pipe barrier; second open gets EWOULDBLOCK; wrong start token mismatch detected; SIGKILL+wait releases old inode lock. `/proc` start identity read exactly, no real PID-reuse stress |
| DR-04 | Negative control detects broken lock discipline | **pass (N)**: unlinking the held lock permits a lock on a different inode while holder is alive. This deliberately demonstrates why unlinking/replacing a namespace lock is unsafe. Fork/dup descriptors can prolong ownership; every holder must close inherited descriptors |
| DR-05 | Stable Neovim binding for Linux lock | **pass (N subset)**: uv file/directory fsync works; `uv.fs_flock`/`fs_fcntl` are nil (unsupported native exports, not runtime setup failures). LuaJIT FFI flock sees conflict/EAGAIN and last-close release. **untested**: eventual binding, cancellation/reentrancy/inherited-FD integration |
| DR-06 | Concurrent initialization, intent before effect, ready last, generation/config identity | **pass (N subset)**: test 08 synchronizes 8 processes on a barrier, then namespace flock serializes init; one bootstrap session and one persisted generation. Checks namespace/protocol/generation/digest and three survival options before accepting ready. **untested**: full protected identity hooks/config and noncooperating endpoint replacement |
| DR-07 | Crash before/after ready: never take over reachable unmarked server | **pass (N subset)**: test 09 has 7 explicit exit points; 4 pre-server points remain absent; post-create/pre-ready remain unmarked and refuse reinitialization; post-ready stays ready |
| DR-08 | Missing versus denied/unresponsive/unmarked/foreign endpoint | **pass (N subset)**: absent path, chmod-000 socket, regular file, symlink, 5s unresponsive socket and closed/stale socket distinguish absent/unavailable/unknown; none of the latter initializes (08/09/11). This does **not** qualify safe automatic stale-socket removal or every Unix error |
| DR-09 | Empty server retains generation without windows/clients | **pass (N subset)**: test 08 removes synthetic bootstrap, list-sessions is empty, ready/options/generation still match and initialize returns ready; no replacement workload/server |
| DR-10 | Stale generation / protected option mismatch must refuse, not repair | **pass (N subset)**: test 08 alters generation and exit-empty separately; initialize returns incompatible and does not repair. Fixture explicitly restores its own changes. **untested**: desired-config digest drift diagnostics and hooks |
| DR-11 | Intent/effect/progress crashes with exact reconciliation | **pass (M only)**: test 03 exits at 9 points; under exact backend operation-index assumption, retry creates precisely two distinct entries total and repeated load is inert. **blocked (native P)**: operation-to-native-effect identity is not established by this ledger |
| DR-12 | Concurrent loads cannot duplicate owner jobs | **pass (M only)**: test 04 runs 3 rounds of 16 barrier-synchronized loaders; exactly 2 model effects each round. A single coarse lock serializes even different owners; not a throughput/per-owner architecture claim. **blocked** for real native recovery |
| DR-13 | Partial recovery leaves unattempted and dormant entries | **pass (M only)**: test 05 recovers first entry, refuses second synthetic cwd, leaves B dormant; no fallback erased. No editor was loaded; native strict-cwd failure is DR-19 |
| DR-14 | Pending/dormant plans survive repeated server loss | **pass (M only)**: test 05 separately loses backend after an unrecorded effect/pending plan, recovers A at g2, loses again before B loads, then recovers A/B at g3 (4 exact entries); names/cwd preserved, fresh epochs. **blocked** pending native evidence |
| DR-15 | Stop/exit suppression survives cleanup failure/loss | **pass (M stop only)**: test 05 preserves durable stopped status through g2/g3, recovers other 3 entries; test 06 retains unknown suppression. **untested**: actual native stop/exit confirmation, partial stop results and registry cleanup failure |
| DR-16 | Ambiguous outcome must block duplicate retry | **pass (M policy only)**: test 06 detects two conflicting operation-index identities, marks first entry unknown, issues no further first-entry effect even across repeated loss, but recovers unattempted second. Native test 10 loses spawn output with no exact operation stamp: cannot reconcile by label/cwd. **blocked (native)**, not an exactly-once proof |
| DR-17 | Live missing jobs stay absent; read-only/stale explicit open never creates | **pass (N subset)**: test 10 removes a synthetic live window and repeated live reads stay absent; this probe simply has no recovery path there. **untested**: future API routing, stale explicit opens, natural exits and authoritative observation completeness |
| DR-18 | Fresh shell uses saved name/cwd, new identities and current shell/env, never former recipe | **pass (N construction + M subset)**: test 10 makes `/bin/sh` in exact private cwd, verifies pane PID/start, cmdline and synthetic current-only env marker in memory; model contains no old command/env recipe and replaces epochs on loss. **untested**: real Neovim-configured shell/flags/env propagation and end-to-end recovery |
| DR-19 | Invalid saved cwd must fail, never substitute | **fail (plain native candidate)**: test 10 submits a nonexistent directory; tmux exits 0, creates shell in private HOME. Negative control is asserted, so the test suite passing records a required behavior failure, not its acceptance. Source spawn.c confirms fallback before fork. Concurrent removal/replacement of cwd is **untested** |
| DR-20 | Revisions/incarnations/tombstones reject stale writers, including after restore | **pass (M only)**: test 07 rejects old revision, deleting incarnation, old incarnation after i2 restore; restores editing context with no eligible stopped jobs. **untested**: all future Sess write paths, concurrent name-uniqueness/create/rename, actual trash integration |
| DR-21 | Tombstone before stop; progress before trash; retain record on partial effects | **pass (M + N rename subset)**: test 12 injects 12 process exits around tombstone, stop effect, suppression and trash; exactly one owner record survives in original or trash location. After effects, deleting/unknown fences recovery or deleted record carries stopped set. This is not native exact-stop evidence |
| DR-22 | Corrupt/incompatible/partial observations preserve last-good data | **pass (M corrupt JSON only)**: test 06 leaves corrupt bytes untouched and raises. **untested**: schema-invalid/incompatible manifests and actual partial backend queries; model has no incomplete-observation overwrite path, not a tested observer implementation |
| DR-23 | Separate manifest then editor snapshot publication, precise partial outcomes | **untested**: no Sess snapshots/editor mutations or real multi-file transaction. Model's partial/unknown strings demonstrate only a policy oracle, not public result propagation |
| DR-24 | Crash durability including filesystem/mount/hardware loss | **blocked**: successful real file/directory fsync calls + pinned kernel/filesystem sources support a conditional local-storage protocol, not a tested power-loss/reboot claim. No physical/VM power-failure or device fault injection. No filesystem beyond the recorded local btrfs tuple qualified |
| DR-25 | Exhaustive irreversible-point and I/R fault coverage | **untested**: mkdir/rmdir crash persistence, failures of every fsync/close/trash/remove boundary, actual interrupted native stop/attach, hostile hooks, partial observation, real owner loading and future implementation/release suites. Required coverage must not be inferred from the finite model |

## Crash matrix and exact finite-run evidence

Final executable evidence was run **three times**, each exit 0, with 12 unittest
methods and the Lua native checks passing. Python method runtimes were 8.133s,
8.230s, 8.262s. Formatting, shell syntax, Python AST parse and diff checks exited
0. Earlier exploratory runs are not included in these counts.

Per run:

- 48 model competing loads (3 × 16 explicit barrier releases); 8 native competing
  initializers (one barrier release). Across final runs: **144 + 24** contenders.
- 9 process exits in recovery: `intent` and `progress`, each at `write`,
  `file-fsync`, `rename`, `directory-fsync`, plus `effect` before progress.
- 1 extra exit after effect before a repeated-loss/pending-plan scenario.
- 7 initializer exits: four `init` publication boundaries, `server-created`,
  `before-ready`, `ready`. A reachable unmarked server is refused, not repaired.
- 12 deletion/trash exits: four `tombstone` publication boundaries, `stop-effect`,
  four `suppression` boundaries, `trash:rename`, `trash:source-directory-fsync`,
  `trash:destination-directory-fsync`.
- Thus **29 deliberate `_exit(73)` child losses per run / 87 total**; separately
  one barrier-held lock owner SIGKILL per run. `_exit` does not flush Python
  buffers but the kernel remains alive, so these are NOT power-loss cuts.
- Two injected EIO controls per run; one real uv EBADF; wrong process-start,
  stale revision/incarnation/generation, conflicting inode locks, wrong endpoint,
  bad protected options, and invalid cwd serve as negative controls.

Bounded sanitized output excerpt (same substantive result in all final runs):

```text
NVIM=0.12.6+v0.12.6
LIBUV=1.52.1
FILE_DIRECTORY_FSYNC_RENAME_TRASH=pass
INVALID_FD_FSYNC=EBADF
UV_FS_FLOCK=nil
UV_FS_FCNTL=nil
LUAJIT_FFI_FLOCK_CONFLICT_CLOSE_RELEASE=pass
NATIVE_INVALID_CWD_EXIT=0; ACTUAL_CWD=PRIVATE_HOME (strict-cwd FAIL)
Ran 12 tests in 8.262s
OK
```

The 5-second unavailable-socket case is an intentionally bounded timeout, not
infrastructure failure. No optional context/web extension was available; `gh`
primary-source fetching and ordinary bounded reads sufficed. `sh tests/run.sh`
was not run: no plugin behavior changed, and the existing plugin suite cannot
qualify this prototype's missing native/durability gates. No I/R pass is claimed.

## Why the model is useful, and why it is insufficient

The model uses a separate JSON effect ledger to stand in for a surviving backend.
It **assumes** complete exact per-operation evidence and serialized atomic effect
plus operation identity. It then rereads under a stable flock, publishes intent
with checked file+directory fsync, reconciles by operation ID, publishes new
identity/progress, and carries unresolved per-owner plans across generations.
Stopped/unknown entries never become automatically eligible. Namespace-owned
incarnation/tombstone state is independent of the movable owner record.

That finite model exposes ordering obligations and provides reproducible oracles;
it does not implement tmux atomic spawning, exact stopping, native epoch hooks,
shape verification, arbitrary hook safety, real editor callbacks, schema
validation, snapshot transactions, or the plugin's write paths. In particular,
test 10's conservative `unknown:no-retry` decision is an explicit policy choice
inside the probe, **not a detected native exact-operation marker**. A tmux shell
can start, naturally exit, or be externally removed before a client records IDs.
Neither a missing window nor a matching name/cwd proves whether that particular
operation executed. A query followed by retry is not a qualified fix.

There is no claim that a finite race run proves atomicity. Namespace locking
coordinates only cooperating clients; native tmux users and arbitrary same-UID
processes do not honor it. Private routing is not authentication. Likewise,
fsync success is conditional on local filesystem/kernel/device semantics; the
mock ledger's durable JSON writes must not be confused with actual workload
persistence or host-reboot semantics.

## Handoff blockers and next action

1. **Strict cwd:** plain tmux 3.8 creation violates the required invalid-cwd
   outcome. Require a separately qualified primitive that fails safely, including
   cwd disappearance/replacement at the creation boundary, or return to a human
   design decision. Preliminary `isdir` alone is not race-safe qualification. Do
   not silently accept HOME substitution or call it recovered successfully.
2. **Exact reconciliation:** qualify a real operation-to-native-effect identity
   protocol covering crash/timeout/early exit and native races. Model token
   lookup cannot pass this gate. Ambiguous outcomes must stay blocked rather
   than duplicate-spawned. Native identity/hooks/conditional-stop evidence from
   the other lanes remains necessary; this lane supplies none of that proof.
3. **Durability qualification:** keep power-loss correctness unproven on the
   recorded tuple. Required further evidence includes filesystem/device failure
   assumptions and actual fault/crash coverage, not a tmpfs/SIGKILL substitute.
   Complete publication/removal/partial-effect error cases before claiming P.
4. **Integration later:** independently test every owner mutation against
   incarnation/revision/tombstone state, last-good schema preservation, pending
   plans across generations, stop suppression, trash restore and exact partial
   outcomes. Select/qualify a usable Neovim lock binding rather than assuming uv
   exposes flock. No implementation authorization follows from the FFI probe.

Main/review owns acceptance, tracker publication and any new design ticket. This
research neither closes #35 nor weakens #30/#32. Only the throwaway evidence
branch is authorized for publication; never merge these disposable probes.
