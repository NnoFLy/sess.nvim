# Research: positive helper execution acknowledgement

## Summary

**Concrete bounded candidate:** a short-lived broker holds a **per-task counting perf event for `sched:sched_process_exec`**, armed after launcher startup but before execution authorization. Given exact launcher/workload binding and enforced authorization gating, a positive count witnesses the authorized chain's successful kernel exec acceptance, including quick exits, without ptrace or a retained command/environment recipe. Acquiring a task reference prevents later PID retargeting; it does not solve the initial numeric-TID attachment race. This is an **investigation recommendation, not observer adoption**: host permissions/kernel facilities require approval, and privilege-changing exec can remove monitoring before the witness.

**Live trade-off:** native execution coverage versus complete acknowledgement. Error-channel/wait/proc alone does not establish universal positive acceptance; ptrace supplies an explicit event but changes privilege/security semantics. No examined candidate preserves execution knowledge through every observer crash. Unknown/no automatic retry remains necessary; exactly-once is not claimed.

## Authority and evidence

Read repository instructions/vocabulary, supplied controlling decisions and corrected reviewed assets, including [Investigate positive helper execution acknowledgement](https://github.com/NnoFLy/sess.nvim/issues/41), [Choose a fail-closed persistent workload launch boundary](https://github.com/NnoFLy/sess.nvim/issues/38), [Specify Sess term command and API behavior](https://github.com/NnoFLy/sess.nvim/issues/29), [Specify safe terminal persistence and reconnection](https://github.com/NnoFLy/sess.nvim/issues/30), [Define persistent terminal acceptance criteria and validation evidence](https://github.com/NnoFLy/sess.nvim/issues/32), and the [immutable helper comparison](https://github.com/NnoFLy/sess.nvim/blob/86ce358003f040561dbbec0c5e04a0b8981c7ffa/docs/research/launch-helper-comparison.md).

**D/direct** = inspected primary source; **inference** = proposed composition. The researcher performed no probes, workloads, live tmux, builds, installs, tests, project edits or tracker mutations. Parent materialization, independent review and baseline repository validation are separate from runtime qualification. Linux v6.12 is the inspected semantic baseline, **not qualification of the historical target or latest kernel**. The separate [Investigate short-lived helper feasibility for exact workload termination](https://github.com/NnoFLy/sess.nvim/issues/39) lane is untouched.

Selected C11/system-libc source-build, private socket/broker-launcher roles, cwd pin/final identity check with accepted residual race, 8 MiB/65,536 entries/configurable five-second setup deadline remain. Ordinary cwd symlinks and actual qualified native libc ENOEXEC fallback are **selected constraints**, not reopened decisions ([latest checkpoint](https://github.com/NnoFLy/sess.nvim/issues/38#issuecomment-6392622988)).

## Findings

### 1. What a positive witness means

**Claim — D; high confidence:** Linux emits `sched_process_exec`, then `PTRACE_EVENT_EXEC`, then proc-connector exec notification **after successful binary-handler completion**. This witnesses new-image acceptance, not application readiness, first userspace instruction, initialization or completion. Dynamic-loader failure can follow kernel acceptance. [Linux `exec_binprm`](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c), [ELF handler](https://github.com/torvalds/linux/blob/v6.12/fs/binfmt_elf.c), [execve](https://man7.org/linux/man-pages/man2/execve.2.html).

“Intended” means the authorized **native attempt chain**. Direct argv resolves in invoking-editor context before placement; native PTY startup changes cwd, replaces `environ`, then calls libc `execvp`. glibc may execute an ENOEXEC file through `/bin/sh`; shebang execution loads its interpreter. Witnessing that shell/interpreter acceptance does not prove script contents or shell text completed. Preserve literal argv and selected fallback; do not re-resolve against final child PATH/cwd or silently refuse native-valid scripts. Runtime libc parity remains unqualified, not undecided behavior. [Pinned Neovim resolution](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/eval.c#L4640-L4701), [PTY startup](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/pty_proc_unix.c#L314-L329), [glibc fallback](https://github.com/bminor/glibc/blob/glibc-2.40/posix/execvpe.c), [script handler](https://github.com/torvalds/linux/blob/v6.12/fs/binfmt_script.c).

### 2. Candidate comparison

| Candidate | Positive evidence and limits | Assessment |
| --- | --- | --- |
| Bounded CLOEXEC error channel + wait/proc | Complete authenticated stage/errno frame proves reported failure. EOF only proves closure. Wait reports exit/signal, not image. `/proc/PID/exe` can change before loading completes. | Necessary diagnostics, insufficient universal witness. |
| Audited reserved helper exit status | After an authenticated gate, if **every** pre-exec normal termination uses only status 127, an exact normal exit 0/nonreserved status can imply replacement by control-flow proof. | Inference, not generic wait semantics. Requires libc/handler audit and exact attribution; workload exit 127, signal death and live commands remain unresolved. |
| `PTRACE_O_TRACEEXEC` | Event stop distinguishes helper startup from later authorized exec and normally holds even a quick command before userspace runs. Persist witness, then detach. | Real witness; **not transparent** privilege/security/signal semantics. Investigation only. |
| **Task-bound counting perf exec tracepoint** | Positive count witnesses successful exec after arming; FD-owned counter survives ordinary target exit. No ring, RAW filename/argv/env samples, BPF or external `perf` executable required. | Preferred bounded candidate for approval/qualification; privilege transitions and host policy limit coverage. |
| Proc connector | Genuine post-success event, but PID/TGID only, no start identity; sends can fail. v6.12 permits non-root proc-group subscription in initial namespaces. | Global notification/loss/PID-reuse correlation is harder than a task counter. |
| `posix_spawn`/vfork; preload/app handshake | Spawn/vfork completion is not unique exec proof. Handshakes require cooperating applications or exclude static/privileged programs. | Not universal minimal substitutes. |

**Support:** D for mechanisms, inference for suitability; high confidence in limitations, medium in proposed compositions. libuv v1.52.1 treats EOF as “okay”; its error writer exits 127 even if writing fails, and its later wait callback distinguishes exit/signal rather than image. Familiar `uv_spawn` normal-start semantics therefore do not provide the requested crash witness. [libuv source](https://github.com/libuv/libuv/blob/v1.52.1/src/unix/process.c), [wait](https://man7.org/linux/man-pages/man2/wait.2.html), [posix_spawn](https://man7.org/linux/man-pages/man3/posix_spawn.3.html).

**Proc trap — D:** `begin_new_exec` installs `mm->exe_file`, replaces mappings and closes CLOEXEC descriptors before ELF stack/mapping/finalization can still fail. PID/starttime identifies process lifetime, not exec generation. Matching exe, comm or “alive” is insufficient. Even perf `COMM_EXEC` occurs too early here: use the successful-exec tracepoint, not rename/prepare-exec. [Exec ordering](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c), [ELF ordering](https://github.com/torvalds/linux/blob/v6.12/fs/binfmt_elf.c).

**Ptrace costs — D:** setuid/setgid/file capabilities may be suppressed or privileged exec refused; detaching cannot undo that. Broker is not naturally the tmux launcher's parent, so LSM/Yama access needs qualification. Do not grant CAP_SYS_PTRACE, weaken policy or enable EXITKILL, which kills tracees on tracer loss. Without EXITKILL, tracer death normally detaches/restarts tracees and can lose evidence. [execve](https://man7.org/linux/man-pages/man2/execve.2.html), [ptrace](https://man7.org/linux/man-pages/man2/ptrace.2.html).

### 3. Concrete counter protocol — inference; medium confidence

While the authenticated launcher remains gated, broker opens a fresh `PERF_TYPE_TRACEPOINT` event for `sched_process_exec`, `pid=launcher_tid`, `cpu=-1`, without inheritance, sampling, remove-on-exec or enable-on-exec. Reset/arm **after helper startup**, before authorization. Launcher's only subsequent successful exec must belong to the authorized native chain. A complete checked read with count >0 is positive; zero/error is never success. Close after bounded classification/publication, not at workload lifetime end.

**D:** perf attaches to a referenced task; `perf_swevent_event` increments count before its nonsampling return; `perf_event_exit_event` explicitly retains FD-owned events; read returns accumulated count. This covers ordinary quick exit without proc sampling or ring-loss inference. [Full inspected v6.12 core](https://cdn.jsdelivr.net/gh/torvalds/linux@v6.12/kernel/events/core.c), [upstream core](https://github.com/torvalds/linux/blob/v6.12/kernel/events/core.c), [tracepoint definition](https://github.com/torvalds/linux/blob/v6.12/include/trace/events/sched.h), [perf API](https://man7.org/linux/man-pages/man2/perf_event_open.2.html).

**Explicit dependency/security boundary:** perf/trace-event kernel configuration, trusted readable tracepoint-ID discovery, bounded FDs and perf/LSM permissions. Kernel execution cannot be excluded; v6.12 `perf_allow_kernel` rejects unprivileged access at paranoia >1. No RAW payload avoids its separate raw-tracepoint check, not all checks. Upstream v6.12 defaults `perf_event_paranoid` to 2, already blocking this unprivileged kernel counter; [tracefs defaults to mode 0700](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/tracefs/inode.c?h=v6.12), which can also prevent tracepoint-ID discovery. Investigate only already-permitted hosts: denied discovery/open/arming must refuse before authorization, without changing sysctls, tracefs permissions, capabilities or security policy. No observer executable, daemon, privilege grant or policy change is adopted. [Perf core](https://github.com/torvalds/linux/blob/v6.12/kernel/events/core.c), [trace-event permissions](https://github.com/torvalds/linux/blob/v6.12/kernel/trace/trace_event_perf.c).

**Critical limit — D:** v6.12 `begin_new_exec` calls `perf_event_exit_task` for a new non-dumpable image before successful-exec notification. Privilege-changing exec can thus detach monitoring before the witness while leaving the FD-owned event readable. Native execution may proceed without incrementing that counter. Positive remains useful; zero stays unknown. Do not “fix” this with `no_new_privs`, tracing or silent command exclusions. [Exec source](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c).

### 4. Exact outcome/crash evidence table

`E` = operation-bound positive event/count; volatile observation alone is not durable evidence.

| Case/window | Permissible conclusion |
| --- | --- |
| Binary/configured shell/shebang/native fallback | E proves authorized exec-chain acceptance, not script/application readiness. Long-running commands need not exit before setup completes. |
| Quick normal exit 0/nonzero | E + exact status: accepted then exited. Without E, normal exit alone is insufficient except the separately audited nonreserved-status inference. |
| Signal death | Durable E: accepted; exact status can additionally identify signal. Without E: helper death, fatal exec failure and workload death remain indistinguishable. |
| Returned setup/exec failure | Complete exact-launcher stage/errno frame: known failure. No intended exec only if launcher ends that attempt chain. Partial frame/EOF: unknown. |
| Post-point-of-no-return failure | Old image cannot report errno; kernel forces fatal SIGSEGV unless another fatal signal is pending. No success event; proc/CLOEXEC changes may already exist. |
| Privilege transition | Monitoring can detach before E while the FD-owned event remains readable: unknown acceptance, not failure-to-launch. Ptrace instead changes native behavior. |
| Editor dies before authorization | Broker proceeds only under explicit delegated publication authority; otherwise abort still-gated helper. “Not attempted” requires every launch path enforcing the gate. |
| Crash after authorization, before exec | Authorization alone: unknown/no-retry; work may subsequently execute. |
| Exec, then broker/editor crash before publication | Surviving broker FD may supply evidence; losing all holders loses volatile knowledge. Empty backend query cannot resolve execution. |
| E durable, crash before reply/attachment | Acceptance remains known; persistence/attachment failure is partial error, not rollback/replay. Liveness/status may remain unknown. |
| Deadline/backend loss | Before authorization: abort only with enforced gate evidence. After authorization: unknown unless exact witness/failure survives. Timeout is not cancellation. |

Expected returned exec errors include **E2BIG despite product caps**; ENOENT for target/script/ELF interpreter; EACCES/noexec; ENOEXEC (possibly native fallback); EINVAL/ELIBBAD/EISDIR; ENOTDIR/ENAMETOOLONG/ELOOP; ETXTBSY; EMFILE/ENFILE; ENOMEM/EIO/EFAULT; EAGAIN and security EPERM. Preserve stage/errno without recipe values. Post-point-of-no-return fatal failure is a distinct path, not an error-channel guarantee. [execve errors](https://man7.org/linux/man-pages/man2/execve.2.html), [kernel fatal path](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c).

### 5. Durable correlation/API — inference

Publish checked file/directory-fsynced **non-secret intent**, exact binding, authorization, then witnessed outcome. Bind operation nonce/revision to owner incarnation, server generation, canonical context, terminal/window/pane/workload epoch and root PID/start identity. Authenticate launcher IPC, acquire its task event while gated, revalidate identity. Native respawn/reused pane never inherits authorization. Peer credentials alone do not prove backend ownership/epoch; atomic native binding remains an open prerequisite.

Store only operation/identity/phase/witness kind, bounded errno/status and partial effects—no command/environment recipe or payload digest. Respect reserved inner TMUX/TMUX_PANE, actual-pane TERM default, captured PWD/NVIM and selected override/unset rules. Request remains transient.

Durable authorization can precede delivery and leave an authorized record with no execution. Recovery uses surviving exact evidence, never resends the old request or clears ambiguity from absence. Even a known-unattempted operation needs old launcher/authority fencing before a new explicitly supplied request. Unknown pending creation cannot become automatic fresh-shell eligibility. This is conservative knowledge, not exactly-once effects.

API separates **accepted**, **accepted then exited**, **known failure**, **unknown acceptance**. Positive count need not imply current liveness/status availability. Broker cannot wait on a nonchild merely by owning its pidfd; tmux owns that child. Adding a parent monitor changes topology and needs approval. Persistence/attachment failures remain errors with committed effects; EOF-based conventional spawn acceptance cannot silently become verified `ok=true` execution. [pidfd](https://man7.org/linux/man-pages/man2/pidfd_open.2.html), [tmux spawn](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c).

## Contradictions

None between inspected primary sources. Tempting interpretations were rejected: proc/exe, CLOEXEC and COMM_EXEC can precede full acceptance. Historical proc-connector privilege claims are not universal: inspected v6.12 permits non-root proc-group binding but restricts namespaces and admits send loss. [Connector access](https://github.com/torvalds/linux/blob/v6.12/drivers/connector/connector.c), [proc notification](https://github.com/torvalds/linux/blob/v6.12/drivers/connector/cn_proc.c).

## Missing evidence and human decision

**Live alternatives, neither selected:**

- **Restricted positive observer:** approve qualification of the short-lived task counter only on already-permitted hosts, with explicit unknown privilege-transition/crash outcomes. Denied access refuses before authorization; no permission weakening, privilege grants or automatic host-policy changes. This narrows practical host support.
- **Native-style launch acceptance:** explicitly reopen the strength of startup success. A normal helper launch-acceptance result would not claim positively witnessed execution, readiness or completion. Exact identity, durable intent, partial outcomes and unknown/no-replay safeguards must remain. This changes the current positive-acknowledgement requirement and needs a live human decision; familiar libuv semantics are not approval.
- **Retain the stronger requirement and continue investigation:** neither candidate must be adopted; a broader compliant witness is not established.

No observer, weaker success contract or command exclusions are adopted. Universal positive acknowledgement preserving all native privilege semantics is **not established**, not universally disproved.

Actual-tuple task attachment/read-after-exit, libc parity, exact tmux binding, durable publication and native no-retry enforcement remain unqualified. This is a useful ordinary-launch candidate, not merely inability to classify crashes and not a command/recovery gate pass.

## Sources and next step

Kept: adjacent Linux exec/ELF/script/perf/connector originals; pinned libuv/Neovim/tmux; glibc 2.40 fallback; original Linux manuals. Confidence: high inspected ordering/limitations, medium counter-protocol feasibility; no runtime qualification. Rolling manuals and v6.12/glibc 2.40 reference baselines do not identify the delivery tuple.

Rejected/deprioritized: tutorials, search summaries as evidence, preload/cooperating-app substitutes, PID-only global events as exact quick-exit oracle. GitHub raw rate limits required rendered originals and a full version-pinned source mirror. Three registered source checks returned **unclear** because automated semantic assessment was unavailable; originals were manually inspected, not automated passes.

Independent primary-source review corroborated the decisive perf/exec/quick-exit claims against version-pinned kernel.org originals. Corrections clarify initial task binding, retained FD versus detached monitoring, default access restrictions and the unselected native-acceptance alternative. The parent ran `sh tests/run.sh` successfully; only Markdown changed and no Markdown formatter is configured. This baseline check is not a persistent-terminal qualification pass.

**Next:** human review of restricted positive observation versus explicitly weaker native-style acceptance or continued investigation; only then narrow binding/acknowledgement qualification. No generic missing-tests checklist substitutes for this decision.
