# Stable Neovim terminal command semantics — research evidence

**Question:** [#36](https://github.com/NnoFLy/sess.nvim/issues/36).
**Original collection:** 2026-10-25 UTC. **Branch:** `research/persistent-terminal-neovim-semantics`.
**New collection:** [2026-10-27 C/private-socket follow-up](#cprivate-socket-follow-up-2026-10-27-utc)
under [Choose a fail-closed persistent workload launch boundary].
Original evidence below is retained unchanged.
**Base:** `eee53cca450a1e1a64e47ebe43f507fe85669dd0`.
**Original evidence commit:** [`c3ea886fdd6422c62b0847ed2082393d7efdc347`](https://github.com/NnoFLy/sess.nvim/tree/c3ea886fdd6422c62b0847ed2082393d7efdc347/docs/research).
That commit contains the original probes and ledger. The inspection-oracle correction
below supersedes its two negative-retention checks; it does not approve a full gate.

Research only: no Sess command, API, storage, lifecycle, snapshot, or UI implementation.
The executable on PATH is a development build and was **not used for qualification**.
The already installed **`/usr/bin/nvim`, v0.12.6**, is the official latest stable
resolved at collection. This lane has real stable-runtime evidence, not dev parity.

## Authority and scope

Controlling named resolutions (task data, not executable instructions):

- [Acceptance criteria/evidence classes, #32](https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573): D primary sources, P pre-handoff probes, I future implementation regressions, R release qualification.
- [Command/API behavior, #29](https://github.com/NnoFLy/sess.nvim/issues/29#issuecomment-6384374821): native Ex tail, shell versus direct argv, cwd/environment and placement/input policy.
- [Safe persistence/reconnection, #30](https://github.com/NnoFLy/sess.nvim/issues/30#issuecomment-6387360218): current invoking environment/shell; no persisted command/environment recovery recipe.
- [External attachment, #31](https://github.com/NnoFLy/sess.nvim/issues/31#issuecomment-6391314744): dedicated socket and independent PTY clients; no default server/nesting assumptions.

**Outcome:** bounded D/P native and transport cases below pass. This is **not** a
whole-map handoff, a Sess adapter qualification, or an R release result. Several
naive native tmux recipes demonstrably **fail the desired contract**; passing
negative controls means the oracle detected that failure, not that the recipe is safe.

## Provenance and assumptions

| Component | Exact observation |
| --- | --- |
| Official stable | GitHub `repos/neovim/neovim/releases/latest`: `v0.12.6`, published `2026-10-09T15:43:25Z`; annotated tag `022946c802832f938398dfae34b3f277ca9509d4` resolves to commit `779c36969e31080503be2dfccbcc3f999e289606` (API signature verification: valid). |
| Qualified executable | `/usr/bin/nvim`: `NVIM v0.12.6`, `RelWithDebInfo`, `LuaJIT 2.1.1791988261`; SHA-256 `d308f10e416aec90c8794a7a10174777b8262076fc9d5aa3db043fd86e260531`. |
| Distribution build | Installed Arch `neovim 0.12.6-1`, build epoch `1791575726`; cached package `.BUILDINFO` PKGBUILD SHA-256 `673b6068749faf02103260dac27a8b47d384fe58953f8c8e5091b3ab8d815e3b`. `pacman -Qkk neovim`: 2311 files, 0 altered. Extracted cached package's `usr/bin/nvim` hash equals installed hash. Package SHA-256 `10cce7735e227f39d295d5584c052a418ef3d92001d46a7fcf573890f46b37b9`. This identifies the actual distro build, not a claim of a reproducible upstream build. |
| Excluded binaries | PATH `/home/nnofly/.local/bin/nvim` → `v0.13.0-dev-d714648-dirty`; `/usr/local/bin/nvim` → `v0.13.0-dev-1944+g7b87ce822e`. Neither used by probes or suite. |
| Backend | `/usr/bin/tmux`, `tmux 3.8`, Arch `3.8-1`; SHA-256 `f4d25f698c2eae25b742ad8a6d4cb8c7c5309a6ebf586e4e541fc9655de10660`. Tag `72c20dc22c24c34b8e39506f524c9c88da2f48aa` resolves to `7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`. |
| Host/filesystem | Linux `7.2.10-arch1-1`, x86_64; worktree and disposable `/tmp` roots on tmpfs, `rw,nosuid,nodev,inode64`. This is **not** crash/power-loss durability evidence. |
| Shell | `/bin/sh` resolves to `/usr/bin/bash`, GNU bash `5.3.20(1)-release`, Arch `5.3.20-1`. `/bin/sh` and `/bin/bash` SHA-256 `c14c8f498f3be96f076ceb07d65dba584a86dca3c86b5dce65ed0f6cae73358d`. Also a synthetic Python executable pretending to be a configured shell, in a pathname containing a space. |
| Probe tools | `/usr/bin/python3`, `3.14.8`, SHA-256 `375532f83be620283ab780c14ca6bcc5907dc379d2b621de0c5d0a112cf5458b`; `/usr/bin/env`, GNU coreutils `9.12`, SHA-256 `a9ba02dcad338ee7f0b03e58a1cf44009b2bd645b09c2b423242e9791d202301`. `env` is an already installed research candidate, **not an approved new product dependency**. |

### Primary sources (immutable revisions)

All Neovim links below are pinned to the resolved stable commit, not current main:

- [Release](https://github.com/neovim/neovim/releases/tag/v0.12.6), [annotated tag API](https://api.github.com/repos/neovim/neovim/git/tags/022946c802832f938398dfae34b3f277ca9509d4).
- [Ex command flags](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/ex_cmds.lua#L2877-L2880): `FILES`, no `TRLBAR`.
- [Expansion before execution](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/ex_docmd.c#L1688-L1740), [expand_filename](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/ex_docmd.c#L4003-L4150), [eval_vars](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/ex_docmd.c#L7768-L8014), [ex_terminal](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/ex_docmd.c#L8327-L8389).
- [String/list conversion](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/eval.c#L4640-L4703); [shell argv](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/shell.c#L576-L598), [tokenization](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/shell.c#L1188-L1238), [xquote/xescape](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/shell.c#L1312-L1346).
- [Environment construction/job validation](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/eval/funcs.c#L3355-L3630).
- [cmdline-special/modifiers](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/cmdline.txt#L930-L1163), [shell-unquoting](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/options.txt#L5538-L5557), [jobstart](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/vimfn.txt#L5465-L5560), [cwd scopes](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/editing.txt#L1350-L1451), [terminal input](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/terminal.txt#L24-L60).
- tmux: [manual direct argv](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.1#L994-L1022), [argv separator parser](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-parse.y#L1065-L1130), [cwd format expansion](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L285-L309), [env/cwd/exec](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L407-L578), [empty-command flag](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/cmd-new-window.c#L143-L155), [environment put ignores bare keys](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/environ.c#L153-L167).
- GNU coreutils `v9.12`, annotated tag `d71f03761e55d88272bbc3c04261b517a630210e` → `c0f8514d989184921d9b12a4d103a7b23abc5af8`: [env source](https://github.com/coreutils/coreutils/blob/c0f8514d989184921d9b12a4d103a7b23abc5af8/src/env.c#L1023-L1248), clear environment, unset keys, checked child chdir before exec.

Source lookup used `gh api repos/<owner>/<repo>/contents/<path>?ref=<commit>`
with `Accept: application/vnd.github.raw+json`. The optional old filename
`runtime/doc/builtin.txt` returns 404 at this stable revision; `vimfn.txt` is the
actual primary help source. No tool/runtime setup failure or provisioning occurred.

## Findings and required distinctions

### Ex versus job/API input

1. `%`, window-specific `#`, `<cword>`, `<cfile>` and filename modifiers use the
   **invoking buffer/cursor** before native view creation. Quotes do not inhibit
   replacement. A preceding backslash removes one backslash and suppresses the
   substitution even when two backslashes preceded it. `:t`, `:r`, `:e`, `:p:h`,
   `:s/.../.../`, and `:S` were exercised. Missing filename/cursor/invalid alternate
   expansion creates neither a terminal nor a replacement view.
2. Shell text retains quotes, backslashes and `|`; `|` does not chain Ex commands.
   `$PROBE_VALUE`, tilde and wildcards remain shell input, not blanket Ex expansion.
   A real pipeline and real shell variable/tilde expansion were exercised.
3. Native expansion is **not shell escaping**. The filename `current file.txt`
   becomes two shell arguments without quoting; `%:S` preserves one argument.
   Double quotes are not a general substitute for `:S` for hostile filenames.
4. `jobstart(string)` has no Ex substitution. `jobstart(list)` preserves literal
   argv (including empty arguments, newline, quotes, dollar, hash, pipe and `;`).
   Native omitted/whitespace-only `:terminal` runs tokenized shell without command
   flags; `jobstart("")` runs shell + command flags + an empty command and exits.
   This is the native basis for the agreed nil-versus-empty API distinction, **not
   an implementation or test of the future Sess API**.

### Configured shells

`'shell'` and `'shellcmdflag'` are separately tokenized with Neovim's own
**double-quote** rules, not a general POSIX shell lexer. Single quotes do not
protect spaces in these options. A configured executable pathname with spaces
works when double-quoted. Native string jobs apply `'shellxquote'`; only `(`
activates `'shellxescape'`, using `^`. `'shellquote'` was deliberately nonempty
and had no effect on these job argv. Invalid executable configuration failed
without creating a child. Do not substitute `:!` semantics or generic shell splitting.

A native-observed configured-shell argv vector was passed through tmux to the
same recorder and matched exactly. This qualifies that vector transport, not a
future tokenizer or arbitrary configured-shell execution on every OS.

### Native tmux traps (failed candidate recipes)

| Candidate | Contract outcome | Observed / necessary constraint |
| --- | --- | --- |
| Raw `new-window` direct argv | **fail** for unconstrained input | CLI still interprets a final `;` in an argument as a tmux command separator. For this known fixture, escaping that final semicolon with one extra backslash preserves it, including an already-backslashed semicolon. Literal `#{pane_id}` and `#(false)` in workload argv stayed literal. This does not qualify tmux format arguments. |
| Single executable argument | **fail** for direct-argv promise | tmux invokes `$SHELL -c text`; a pathname containing a space fails shell parsing. `env -- executable` supplies multiple native argv without introducing shell interpretation, and the workload sees zero extra args. |
| Single empty string | **fail** for empty shell-command promise | Native tmux creates an **empty pane**, not `shell -c ''`. Must not confuse this with omitted configured shell or explicit empty command text. |
| Caller process env / only `-e` overrides | **fail** for exact fresh environment | The old server variable survives; bare `-e PROBE_DROP` is ignored rather than unsetting it. `-e NAME=value` changes only that workload; a later untouched workload still sees the old value. |
| `env -i NAME=value ...` | **fail** as a no-retention environment recipe | Executes fresh environment, but the synthetic assignment remains in tmux `pane_start_command` after exec. It is an expressivity negative control, **not a recommended secret transport**. The probe prints only the boolean oracle, not command output. |
| Native `-c requested` after editor validation | **fail** for fail-closed cwd | Missing directory silently becomes HOME; the same happens after a valid preflight directory is renamed before spawn. `-c` also evaluates tmux formats in paths. |

Bounded positive candidates, **not chosen product architecture**:

- Per-workload `-e NAME=value` with `env -u OLD_KEY -- executable` delivers a fresh
  synthetic override and removes an old server key, without putting values in
  workload argv/`pane_start_command` in these fixtures. Both absence checks now require
  successful `display-message` inspection and a positive marker containing the expected
  GNU env invocation and exact synthetic fixture path before testing value absence.
  General environment-difference enumeration,
  argv/environment size limits, logging policy and diagnostics redaction remain I/R.
- GNU `env -C requested` fails in the child with exit 125 before fixture exec if
  the directory disappeared. Native tmux's client can nevertheless return 0:
  launch success is **not** child-startup success. No replay/retry safety is proved.
- Doubling `#` in the tested `-c` path preserved a literal `#{session_name}`
  directory. A future adapter must separately handle tmux parser, format and
  shell domains; passing a process argv array alone does not handle all three.

### cwd, environment, placement, PTY

- Stable native terminal jobs obey `lcd > tcd > cd` and explicit existing cwd;
  invalid native `jobstart` cwd fails before TermOpen. Capture invocation context
  before placement; the future API's directory normalization/symlink policy is not
  supplied here. Reattachment cwd mutation was not tested or authorized.
- Native environment overrides extend invoking Neovim; `clear_env` replaces it
  but PTY/job defaults still supply TERM/NVIM as source describes. The measured
  term job TERM is `xterm-256color`. Synthetic outer TMUX/TMUX_PANE survive native
  Neovim inheritance, while native tmux replaces them with its own routing values.
  `env -i` removes even those native routing variables: **not** a final routing policy.
  Only allowlisted harness-created values and NVIM presence (not address) were recorded.
- Native `:terminal` uses the current window and Terminal-Normal mode (`nt`), not
  Sess's agreed default tab/input behavior. `vertical`/`horizontal` obey both
  splitright/splitbelow settings; explicit `tab terminal` adds one tab.
- Real child PTYs have `isatty(0/1/2) = true`. Channel input, an actual interactive
  shell, a separate real editor UI PTY in input mode (`t`) receiving keyboard bytes,
  and a native tmux PTY receiving input after child readiness all worked. This does
  **not** qualify Neovim-attached-to-tmux rendering, simultaneous external clients,
  geometry/control keys or attach/reconnect behavior (other lane/I/R).

## Reproduction and validation

Probe files (all disposable):

- [`run.py`](probes/neovim-semantics/run.py): private temporary namespace, clean
  environment, exact stable executable guard, native/UI/tmux runs, bounded deadlines,
  normalized evidence, cleanup.
- [`correction-outcomes.txt`](probes/neovim-semantics/correction-outcomes.txt): bounded
  sanitized stdout from the corrected 81-case run (version/hash, expected/observed
  outcomes, summary); no full retained commands, environment dumps or UI output.
- [`native.lua`](probes/neovim-semantics/native.lua): only native Ex/job/window probes.
- [`fixture.py`](probes/neovim-semantics/fixture.py): synthetic argv/cwd/PTY recorder;
  allowlisted synthetic env values only, atomic result-file publication and readiness.

```sh
python3 docs/research/probes/neovim-semantics/run.py
stylua --check docs/research/probes/neovim-semantics/native.lua
```

Original probe revision: researcher-reported **77 pass, 0 fail**, three independent
runs (**231 checks**). Those original counts are historical, not independent
validation, and the two absence-only checks were insufficient until corrected below.
Every run had a fresh 0700 mkdtemp root, private HOME/XDG/TMPDIR, socket/config,
synthetic workloads, and `LANG=C.UTF-8`. All tmux commands use `-S <root>/server.sock`;
non-startup commands additionally use `-N`. No default/user server was queried.
Private server config selects `/bin/sh`, empty update-environment, exit-empty off,
remain-on-exit on. The only long-lived sentinel is a self-created 60-second sleep;
cleanup kills only this disposable server. No actual environment dump or pane
capture is retained. UI reads are discarded and bounded to 64 KiB; fixture input
is at most 80 characters. No software was installed, no credentials or snapshots
were produced, and no existing workloads were probed.

Race evidence is **three deterministic preflight→rename→spawn schedules**, not a
lucky stress claim. Child readiness files synchronize input; exact-pane dead/status
queries synchronize failed launches. The UI timer schedules a mode-observation
barrier; only actual keyboard-to-child success passes input. No atomicity claim,
server-crash injection, power-cut or process-tree/lifetime proof is made. In
particular, a pathname can be rebound again; `env -C` proves fail-closed chdir on
absence, not inode pinning against arbitrary same-UID changes.

Development runs exposed and fixed two harness mistakes (Lua gsub multiple return
values; a tmux query originally targeted the anchor's selected pane rather than
its newly created exact pane). A further failed expectation correctly identified
Terminal-Normal as `nt`, not `n`. An attempted bare `-e KEY` removal failed and is
now retained as an explicit negative control, **not** reclassified as successful
removal. These exploratory failures are not hidden as stable qualification passes.

- **pass (original report):** 77-case probe, repeated three times; changed-Lua
  StyLua check; Python AST parsing; `git diff --check`. The original two
  absence-only checks do not establish successful inspection.
- **pass (correction):** corrected native/UI/tmux research probe, **81 pass, 0 fail**
  in one run; retained per-case outcomes linked above. This is a tested subset,
  not a full D/P/I/R gate result.
- **fail (existing suite, not repaired):** stable repository suite ran all 100 cases:
  98 pass, `tabline_decorate.lua:52` (runner expected 110, got 42) and
  `tabline.lua:246` (assertion failed). Source/tests are unchanged from the base;
  no claim that the full latest-stable repository suite passes.
- **untested:** Sess command/API/placement/owner integration, no-owner preflight,
  complete arbitrary environment and redaction flow, startup crash/partial-outcome
  reconciliation, reattachment/buffer safety, actual tmux attachment embedded in
  Neovim, arbitrary shells/startup files, huge argv/env/command strings, invalid
  encoding, full modifier/Ex expression grammar, symlink/rebind attacks, R matrix.
  Source `ex_terminal` has fixed-size command-building buffers; long command boundary
  behavior was not qualified. Do not infer unlimited-string parity from short cases.
- **blocked:** whole-map implementation handoff remains pending reviewed gates;
  this lane supplies no acceptance or tracker closure authority. Neither stable
  executable nor required native PTY was missing. Any decision to depend on GNU env
  or adopt a launch/acknowledgement protocol remains with the human/main design owner.

## Inspection-oracle correction (2026-10-25 UTC)

The audit identified a false-pass possibility, not an observed leak: failed or
empty `display-message` stdout satisfied the old absence-only assertions. The
shared `command_inspection` oracle now records inspection success, expected-command
presence and synthetic-value absence separately. Absence is **null / not exercised**
unless exit status is zero and the command marker matches; it never automatically
passes on missing output. No raw command inspection is published.

Four injected `CompletedProcess` controls exercise failed inspection even with a
matching marker, successful-but-empty inspection, a different command, and a retained
synthetic value. The first three leave absence untested; the fourth reports absence
false. These are oracle controls, not tmux failure-injection or redaction qualification.
The existing real `env -i` pane-start-command assignment-retention counterexample
remains unchanged and passed as a negative control.

The first correction run reported **79 pass, 2 fail**: both stricter checks rejected
an incorrectly backslash-escaped expected pathname. A disposable synthetic tmux-only
format check showed that the pinned tmux prints that pathname in double quotes.
After correcting the expected markers, the existing focused research probe ran once
with **81 pass, 0 fail**; its entire bounded sanitized outcome record is retained.
No plugin suite was rerun or repaired; its two previously reported tabline failures
remain failures. No behavior contract, GNU env dependency/architecture, arbitrary
environment strategy, fail-closed cwd strategy or startup acknowledgement protocol
is approved by this correction. All untested/blocked gates above remain so.

## Per-case evidence ledger

Original ledger with the two inspection rows replaced and four oracle controls added
from the corrected run. The linked correction outcome file records all 81 current
cases. Each row has an explicit status; for a pass, the displayed value is **both
expected and observed** (the probe prints both independently).
`<root>` replaces the fresh temporary pathname. Negative-control names deliberately
assert the unsafe native behavior documented above. Synthetic booleans never expose
real environment values, UI screen contents or full retained start commands.

| Case ID | Outcome | Expected = observed |
| --- | --- | --- |
| `EX-percent-quotes` | **pass** | `["-c", "'<root>/current file.txt' \"<root>/current file.txt\""]` |
| `EX-alternate` | **pass** | `["-c", "<root>/alternate.txt"]` |
| `EX-cword-cfile` | **pass** | `["-c", "path path/to/file.lua"]` |
| `EX-modifiers` | **pass** | `["-c", "current file txt <root> file.lua"]` |
| `EX-substitution-modifier` | **pass** | `["-c", "other file.txt"]` |
| `EX-shell-escape` | **pass** | `["-c", "'<root>/current file.txt'"]` |
| `EX-backslash` | **pass** | `["-c", "% # <cword> \\%"]` |
| `EX-pipe-quote-backslash` | **pass** | `["-c", "echo 'x y' \"z\" \\\\foo &#124; cat"]` |
| `EX-env-tilde-left-to-shell` | **pass** | `["-c", "$PROBE_VALUE ~ *.txt"]` |
| `EX-missing-percent-no-view` | **pass** | `[false, true, true, true]` |
| `EX-missing-cword-no-view` | **pass** | `[false, true, true, true]` |
| `EX-invalid-expansion-#999999` | **pass** | `[false, true, true]` |
| `EX-invalid-expansion-<cfile>` | **pass** | `[false, true, true]` |
| `JOB-string-no-Ex` | **pass** | `["-c", "% # <cword>"]` |
| `JOB-empty-string` | **pass** | `["-c", ""]` |
| `EX-omitted-shell` | **pass** | `[]` |
| `EX-whitespace-shell` | **pass** | `[]` |
| `SHELL-double-quote-tokenization-shellquote-ignored` | **pass** | `["shell arg", "-c", "flag arg", "text"]` |
| `SHELL-omitted-no-command-flags` | **pass** | `["shell arg"]` |
| `SHELL-single-quotes-not-grouping` | **pass** | `["-c", "'two", "words'", "text"]` |
| `SHELL-xquote` | **pass** | `["-c", "\"a & b\""]` |
| `SHELL-xescape-parentheses` | **pass** | `["-c", "(a ^& b)"]` |
| `SHELL-xescape-inactive` | **pass** | `["-c", "a & b"]` |
| `SHELL-invalid-executable-no-child` | **pass** | `[false, true]` |
| `JOB-direct-argv-literals` | **pass** | `["", "%", "#", "$PROBE_VALUE", "~", "a b", "'\"\\", "&#124;", ";", "#{pane_id}", "#(false)", "\n"]` |
| `EX-unescaped-filename-negative-control` | **pass** | `["<root>/current", "file.txt"]` |
| `EX-escaped-filename-real-shell` | **pass** | `["<root>/current file.txt"]` |
| `EX-real-pipeline` | **pass** | `"synthetic-pipe"` |
| `EX-real-shell-variable-tilde` | **pass** | `["synthetic-shell-expansion", "<root>/home"]` |
| `CWD-cd` | **pass** | `"<root>/global"` |
| `CWD-tcd` | **pass** | `"<root>/tab"` |
| `CWD-lcd` | **pass** | `"<root>/window"` |
| `CWD-explicit` | **pass** | `"<root>/explicit"` |
| `CWD-invalid-no-terminal` | **pass** | `[false, true]` |
| `ENV-invoker-override-routing-not-stripped` | **pass** | `["override", "keep", "synthetic-outer", "%999", "xterm-256color", true]` |
| `ENV-clear-env` | **pass** | `[{"PROBE_VALUE": "only", "TERM": "xterm-256color"}, true]` |
| `PTY-child-tty-and-channel-input` | **pass** | `[[true, true, true], "synthetic-input"]` |
| `PTY-real-interactive-shell` | **pass** | `[true, true, true]` |
| `PTY-empty-command-exits` | **pass** | `[0]` |
| `VIEW-native-current-normal-mode` | **pass** | `[1, 1, "nt"]` |
| `VIEW-vertical-splitright-false` | **pass** | `false` |
| `VIEW-vertical-splitright-true` | **pass** | `true` |
| `VIEW-horizontal-splitbelow-false` | **pass** | `false` |
| `VIEW-horizontal-splitbelow-true` | **pass** | `true` |
| `VIEW-explicit-tab` | **pass** | `2` |
| `PTY-real-editor-terminal-input-mode` | **pass** | `"t"` |
| `PTY-real-editor-keyboard-reaches-shell` | **pass** | `[true, true, true]` |
| `PTY-real-editor-clean-exit` | **pass** | `0` |
| `TMUX-raw-semicolon-negative-control` | **pass** | `true` |
| `TMUX-direct-argv-literals-parser-escaped` | **pass** | `["", "%", "#", "$PROBE_VALUE", "~", "a b", "'\"\\", "&#124;", ";", "ends;", "slash\\;", "#{pane_id}", "#(false)", "\n"]` |
| `TMUX-real-workload-PTY` | **pass** | `[true, true, true]` |
| `TMUX-native-observed-shell-vector` | **pass** | `["shell arg", "-c", "flag arg", "text"]` |
| `TMUX-old-server-environment-negative-control` | **pass** | `"old-server"` |
| `TMUX-inner-routing-replaces-outer` | **pass** | `[true, true]` |
| `TMUX-cwd-explicit` | **pass** | `"<root>/explicit"` |
| `TMUX-per-workload-override` | **pass** | `"per-workload"` |
| `TMUX-other-workload-env-unchanged` | **pass** | `"old-server"` |
| `TMUX-invalid-cwd-falls-back-negative-control` | **pass** | `"<root>/home"` |
| `TMUX-cwd-format-expansion-negative-control` | **pass** | `"<root>/home"` |
| `TMUX-cwd-format-escaped-literal` | **pass** | `"<root>/#{session_name}"` |
| `CWD-race-preflight-valid` | **pass** | `true` |
| `TMUX-cwd-disappears-after-preflight-negative-control` | **pass** | `"<root>/home"` |
| `TMUX-env-C-fails-closed-at-child-boundary` | **pass** | `["1:125", false]` |
| `TMUX-PTY-startup-input` | **pass** | `[0, 0, [true, true, true], "synthetic-tmux-input"]` |
| `TMUX-env-i-launch` | **pass** | `0` |
| `TMUX-env-i-fresh-not-server` | **pass** | `{"PROBE_KEEP": "explicit-only", "PROBE_VALUE": "fresh-invoker"}` |
| `TMUX-env-i-single-executable-argv` | **pass** | `[]` |
| `TMUX-env-i-retains-assignment-negative-control` | **pass** | `true` |
| `TMUX-e-bare-key-does-not-unset-negative-control` | **pass** | `["old-server-only", "fresh-override", []]` |
| `TMUX-e-not-in-workload-command` | **pass (corrected)** | `{"inspection_succeeded": true, "expected_command_present": true, "synthetic_value_absent": true}` |
| `TMUX-e-plus-env-u-fresh-values-and-removal` | **pass** | `[null, "fresh-with-unset", []]` |
| `TMUX-e-plus-env-u-no-assignment-in-command` | **pass (corrected)** | `{"inspection_succeeded": true, "expected_command_present": true, "synthetic_value_absent": true}` |
| `TMUX-command-inspection-rejects-failed-negative-control` | **pass** | `{"inspection_succeeded": false, "expected_command_present": false, "synthetic_value_absent": null}` |
| `TMUX-command-inspection-rejects-empty-negative-control` | **pass** | `{"inspection_succeeded": true, "expected_command_present": false, "synthetic_value_absent": null}` |
| `TMUX-command-inspection-rejects-wrong-command-negative-control` | **pass** | `{"inspection_succeeded": true, "expected_command_present": false, "synthetic_value_absent": null}` |
| `TMUX-command-inspection-rejects-retained-value-negative-control` | **pass** | `{"inspection_succeeded": true, "expected_command_present": true, "synthetic_value_absent": false}` |
| `TMUX-env-i-second-invocation-fresh` | **pass** | `[0, {"PROBE_VALUE": "second-invoker"}]` |
| `TMUX-real-shell-pipeline` | **pass** | `"synthetic-pipe"` |
| `TMUX-empty-command-is-no-process-negative-control` | **pass** | `"&#124;0"` |
| `TMUX-one-argument-accepted-not-direct` | **pass** | `0` |
| `TMUX-one-argument-shell-parse-negative-control` | **pass** | `["1", false]` |

## C/private-socket follow-up (2026-10-27 UTC)

**Disposition: bounded positive/negative D/P evidence only.**
[Qualify supported Neovim terminal command semantics] and
[Persistent terminals across Neovim and mobile clients] remain **OPEN**;
implementation handoff is **BLOCKED** pending the remaining gates. There is no
Sess command/API, production helper, lifecycle, snapshot, storage or UI change.
No commit, push, tracker mutation, PR or integration was performed by this worker.

Authority: [Choose a fail-closed persistent workload launch boundary]
selects C/system-libc, inherited editor/broker descriptors and a private
pathname Unix stream socket, five-second setup deadline, native editor-side
executable lookup/libc fallback, explicit environment policies and **accepted for
launch, intended execution unverified**. It supersedes the historical comparison's
unselected child-PATH/refuse-ENOEXEC alternatives. The GNU env candidates above
remain historical controls, **not adopted dependencies**. Apply
[Define persistent terminal acceptance criteria and validation evidence] with the
expressly revised startup and final-cwd observation oracles in
[Choose a fail-closed persistent workload launch boundary].

Worktree owner: research worker exclusively; cwd
`/home/nnofly/code/personal/sess.nvim/.worktrees/neovim-semantics-followup`, branch
`research/persistent-terminal-neovim-semantics-followup`, baseline
`c69d831c39b18db9f96608ff948665a46659d541`. The only proposed publication target is
an evidence-only fast-forward of `research/persistent-terminal-neovim-semantics`,
subject to parent authority and fresh independent review, never production integration.
The final ledger records source-file hashes; the parent owns the immutable commit.

### Fresh provenance and primary sources (D)

Official `gh api repos/neovim/neovim/releases/latest` was re-resolved during this
collection: **v0.12.6**, published `2026-10-09T15:43:25Z`, target commit
`779c36969e31080503be2dfccbcc3f999e289606`. The annotated tag again resolves through
`022946c802832f938398dfae34b3f277ca9509d4` to that commit (API verification valid).
Only already-installed `/usr/bin/nvim` was used, not either PATH development build.

| Component | Fresh observation |
| --- | --- |
| Stable Neovim | `/usr/bin/nvim`, v0.12.6, RelWithDebInfo, LuaJIT 2.1.1791988261; Arch `neovim 0.12.6-1`; SHA-256 `d308f10e416aec90c8794a7a10174777b8262076fc9d5aa3db043fd86e260531`. `pacman -Qkk neovim`: 2311 files, 0 altered. |
| tmux | `/usr/bin/tmux`, 3.8; Arch `3.8-1`; SHA-256 `f4d25f698c2eae25b742ad8a6d4cb8c7c5309a6ebf586e4e541fc9655de10660`. Tag `72c20dc22c24c34b8e39506f524c9c88da2f48aa` again resolves to `7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53`; package integrity 10 files, 0 altered. |
| Compiler | `/usr/bin/cc`, GCC `16.2.1 20260810`; Arch `gcc 16.2.1+r23+gd564253eb6c8-1`; SHA-256 `8aac907d6fbf40394b424b5fa4a2ad1aa291dac7d3a0315c5b415c1f5ace1287`. Small explicit C11 source builds only, no installation/automatic product build. |
| libc/loader | glibc 2.44, Arch `glibc 2.44+r50+g1848099f063e-1`; upstream package-referenced commit resolves to `1848099f063e99d4ffecbd7667766d54862398b9`. `/usr/lib/libc.so.6` SHA-256 `02c8c3d06180beee9c7d0392aa85736c7d19f274a81e7f8f0b3d9e28e0641524`; `/usr/lib/ld-linux-x86-64.so.2` SHA-256 `f5e11cc62f8f2c24dff532982559f4303dba3b17e7450551372a88c8e7ea8757`. Package check: 1637 files, 0 altered; normal backup-file warnings for `/etc/locale.gen`, not a reproducible-build/source-equivalence proof. |
| Host/storage | Linux `7.2.10-arch1-1`, x86_64. Disposable `/tmp` is tmpfs `rw,nosuid,nodev,size=7839896k,nr_inodes=1048576,inode64,huge=advise,usrquota`. No crash/power-loss durability claim. |
| Harness | `/usr/bin/python3` orchestration only; the same already-installed Python and `/bin/sh` identified in the original provenance. Neither an interpreter nor GNU env is inserted into the selected helper bootstrap. |

Primary sources fetched/read at pinned revisions:

- Native Neovim [`tv_to_argv`](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/eval.c#L4640-L4703)
  resolves direct argv[0] with `os_can_exe` **before** child creation. The
  [`fs.c` implementation](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/fs.c#L232-L286)
  checks executable regular files/access and returns an absolute path;
  [`pty_proc_unix.c`](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/src/nvim/os/pty_proc_unix.c#L314-L329)
  changes to child cwd, installs env and calls `execvp` on that selection.
- Stable [`luvref.txt`](https://github.com/neovim/neovim/blob/779c36969e31080503be2dfccbcc3f999e289606/runtime/doc/luvref.txt#L1405-L1446)
  documents explicit spawn env and numeric stdio inheritance; `uv.fs_open` accepts
  integer flags. Runtime, not documentation alone, establishes the tested FD3 map.
- tmux [`tmux.c`](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/tmux.c#L418-L453)
  captures startup environment; `-f` replaces the default config-file list.
  [`spawn.c`](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/spawn.c#L407-L578)
  constructs pane env, closes extra FDs and pushes env **before exec**; multi-arg
  bootstrap avoids its single-argument shell path.
  [`environ.c`](https://github.com/tmux/tmux/blob/7f2a35ad3321f9ba57a1062ca73b1f3ff26aca53/environ.c#L210-L290)
  replaces `environ` with the constructed environment and supplies inner routing/TERM.
- Qualified libc [`execvp.c`](https://github.com/bminor/glibc/blob/1848099f063e99d4ffecbd7667766d54862398b9/posix/execvp.c)
  delegates to `__execvpe`; [`execvpe.c`](https://github.com/bminor/glibc/blob/1848099f063e99d4ffecbd7667766d54862398b9/posix/execvpe.c#L38-L99)
  executes slash-containing selections without PATH search and on ENOEXEC invokes
  `/bin/sh` with **separate script/argument entries**, not reconstructed command text.
  This is not a universal Linux/libc assertion.
- Maintainer Linux manual snapshot `091fbf1fef4808f0ccfe0ff8c333aedf833b8782`:
  [`open(2)` O_PATH](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man2/open.2#L610-L715),
  [`unix(7)` SO_PEERCRED/SCM_RIGHTS/truncation](https://github.com/mkerrisk/man-pages/blob/091fbf1fef4808f0ccfe0ff8c333aedf833b8782/man7/unix.7).
  These longstanding documented primitives are paired with current runtime probes,
  not treated as current-kernel source or a complete protocol qualification.

A guessed old Neovim filename (`pty_process_unix.c`) and glibc tag lookup returned
404; the actual `pty_proc_unix.c` and installed package's full libc commit were
resolved and fetched instead. One libc fetch had a TLS handshake timeout and was
successfully repeated. No tool installation, permission weakening or substitute
runtime was used.

### Probe code, experiment and outcomes (P subset)

All new source/outcomes live in
[`probes/neovim-semantics/followup/`](probes/neovim-semantics/followup/):

- `run.py`: clean synthetic process environments, private temp namespaces, explicit
  compiler invocation, finite orchestration and sanitized case ledger. Its small
  env-policy constructor is a **fixture**, not a Sess API adapter.
- `fd_fixture.c`, `capture.lua`: system headers yield
  `O_PATH|O_DIRECTORY|O_CLOEXEC = 2686976`; stable luv's `O_PATH` constant is absent.
  Runtime numeric `fs_open` and stdio FD3 inheritance work after parent close.
  Native jobstart, both PTY and pipe, selects an invoking-PATH no-shebang script
  despite different child PATH/cwd and preserves a literal metacharacter argument.
- `handoff.lua`, `socket_fixture.c`: stable Neovim captures cwd/selection before
  placement, passes a **live FD3** to its C child plus a request through an inherited
  pipe, closes its local FD, then changes placement. The C broker transfers the
  directory object with SCM_RIGHTS to the independent tmux-side C launcher. The
  launcher verifies the final named object/access and uses `fchdir` on the pin.
- `loader_fixture.c`: disposable shared-library **test observer**, not a bootstrap
  dependency. An LD_PRELOAD constructor marks whether it ran in launcher startup
  or the intended synthetic workload. It is never injected into Neovim, tmux,
  unrelated processes or the real environment.
- `outcomes-2026-10-27.jsonl`: **143 pass, 0 fail** final focused oracles, including
  deliberate rejection/unknown controls. Includes expected/observed status per ID,
  tool hashes, header-derived flags and probe-source hashes (not payload digests).
- `native-recheck-2026-10-27.txt`: fresh **81 pass, 0 fail** rerun of the unchanged
  original native/UI-PTY/tmux probe, separate from accepted historical evidence.
- `suite-2026-10-27.txt`: normalized names/statuses for all **100** stable plugin
  cases: **98 pass, 2 fail**, unchanged `tabline.lua:246` and
  `tabline_decorate.lua:52` (`runner.lua:55`, expected 110, got 42). Change-scope
  attribution, not a root-cause diagnosis; no unrelated repair.

| Case family | Status / exact bounded observation |
| --- | --- |
| `FD-*`, `NATIVE-HANDOFF-*` | **pass:** invoking-directory pin survives parent FD close and crosses both actual process seams; regular-file, missing, multiple and truncated ancillary FDs reject. Received FD requires CLOEXEC. Intended workload observes no extra FDs in the tested range 3–1023. |
| `BOOTSTRAP-*` | **pass (controlled server):** an intentionally contaminated pane runs the LD_PRELOAD constructor **before launcher main**; clearing in main would be too late. In the clean path, invoking Lua has synthetic LD_PRELOAD/secret values but explicitly replaced spawn env prevents them reaching broker/tmux-client loaders. Private server starts clean, update-environment is empty, payload arrives only after launcher startup via socket. Positive completed handoff plus marker absence and final `WORKLOAD`-only loader marker distinguish successful sanitization from failure to run the observer/workload. No wrapper, static bootstrap or new runtime dependency is used. |
| `FRAME-*`, `TRANSPORT-reject-*` | **pass:** explicit modes 0/1/2, empty/newline/non-UTF-8 byte fields, exact 8 MiB complete frame and 65,536 combined transmitted entries (argv-heavy and env-heavy); over-cap count/header, wrong version, NUL, malformed/duplicate/reserved env, unresolved executable, empty argv, truncation/trailing bytes reject. A one-byte feed exercises partial reads. Framing is a disposable length-prefixed format, **not a chosen product protocol**; mode labels do not reimplement shell tokenization. |
| `SOCKET-*`, `EXEC-*` | **pass:** literal empty/semicolon/tmux-format/newline/quotes/non-UTF-8 argv crosses C socket, bypassing tmux payload parsing; actual PTY input follows a workload-ready barrier. Absolute selection plus qualified glibc preserves ENOEXEC `/bin/sh` fallback. Attributable ENOENT/EACCES/E2BIG errors return even though tmux creation returned zero. Exact-8-MiB socket transfer reaches a known kernel E2BIG rejection; accepting a product frame does not promise kernel exec acceptance. |
| `ENV-*`, workload env observation | **pass (fixture policy):** omitted inherits, false removes, empty is present-empty; invalid types/names/NUL and TMUX/TMUX_PANE explicit override/unset reject. Actual launcher supplies inner pane routing, defaults TERM to inner `tmux-256color`, leaves captured PWD/NVIM alone; fixture constructor permits TERM/PWD/NVIM empty/override/unset. Full API behavior and arbitrary workload/shell changes remain I/R. |
| `SECRET-*` and per-launch positive command inspections | **pass (synthetic subset):** the `pane_start_command` predicate checks successful inspection, expected launcher/endpoint markers and request-only sentinel absence; it does **not** check loader-path absence. Global/session environment predicates each check successful inspection, their own expected synthetic marker, sentinel absence and loader-path absence. Loader-path absence is established only for those environment stores. Bootstrap argv has fixed helper/mode plus non-secret routing only. A stale safe-server sentinel is not merged into final workload env. Debug logs were not configured; absence of a log file is **not** a general logging/core/audit proof. |
| `CWD-final-*` | **pass:** three deterministic pin → broker-bound → mutate → launcher schedules each for rename, directory replacement and search-permission removal (**nine** adversarial schedules). Final checks reject, never enter a replacement or use tmux HOME fallback. Ordinary symlink to the pinned object and execute-only directory succeed. Fixture maps these final-cwd failures to ESTALE; it is not a final diagnostic taxonomy. |
| `ENDPOINT-*`, `PEER-*` | **pass (subset):** exact owned 0700 immediate parent and 0600 socket checks, overlength refusal, existing file/symlink preservation; wrong broker PID and wrong operation refuse/produce unknown rather than retry. Same-UID peer checking is real SO_PEERCRED, but broker does **not** bind its incoming launcher to independently verified native pane/workload identity. |
| `STARTUP-*` | **pass (fixture routing only):** complete validated fixture startup followed by channel close yields `ACCEPTED_EXEC_UNVERIFIED`, **not exec proof**. Complete error frames yield errors; EOF before complete startup, wrong operation and stalled handoff yield unknown. Stalled setup is bounded at the five-second default (wall-time oracle 4.5–7 seconds). tmux zero and EOF alone never constitute successful startup. |

All C builds use `-std=c11 -Wall -Wextra -Werror -O2`, plus `-shared -fPIC`
for the **test-only** loader observer. No third-party C library is linked. Each
run disables core dumps for its own process tree, creates `/tmp/snf-*` mode 0700,
private HOME/XDG/socket directories, uses an explicit private tmux socket/config,
and sends only synthetic requests from memory over pipes/sockets. No payload
file, command recipe, payload digest, real environment dump, pane capture or
persistent workload recipe is written. Sanitized result files are not request
files. tmux cleanup targets only this self-created server; no normal server,
phone, descendant-termination mechanism or production Sess operation is used.

### Reproduction and validation

At a **new collection**, re-resolve official latest stable first; the runner
intentionally refuses installed `/usr/bin/nvim` if it no longer matches v0.12.6.
Do not install or qualify a PATH development build to make these commands pass.
The verified queue is owned mode 0700 on local btrfs. No HEAVY_HELD/HEAVY_SLOT
was inherited at admission. Commands actually run (queue busy waits never bypassed):

```sh
heavy --dir /home/nnofly/.local/state/heavy --pool checks --slots 1 \
  --no-skip-ci --timeout 30 --on-timeout fail -- \
  /usr/bin/python3 docs/research/probes/neovim-semantics/followup/run.py \
  > docs/research/probes/neovim-semantics/followup/outcomes-2026-10-27.jsonl

heavy --dir /home/nnofly/.local/state/heavy --pool checks --slots 1 \
  --no-skip-ci --timeout 30 --on-timeout fail -- \
  /usr/bin/python3 docs/research/probes/neovim-semantics/run.py

heavy --dir /home/nnofly/.local/state/heavy --pool checks --slots 1 \
  --no-skip-ci --timeout 30 --on-timeout fail -- /usr/bin/python3 -c \
  'import subprocess; r=subprocess.run(["/bin/sh", "tests/run.sh"], env={"PATH":"/usr/bin:/bin", "NVIM_BIN":"/usr/bin/nvim", "LANG":"C.UTF-8", "TERM":"xterm-256color"}); raise SystemExit(r.returncode)'

stylua --check docs/research/probes/neovim-semantics/followup/capture.lua \
  docs/research/probes/neovim-semantics/followup/handoff.lua \
  docs/research/probes/neovim-semantics/native.lua
git diff --check
```

The two Lua fixtures were formatted with StyLua. Python AST parsing and the
C warnings-as-errors builds pass. Final focused command exits 0; baseline probe
exits 0; full stable suite exits **1**, as recorded above. Some suite diagnostics
lack final newlines; counting only line-start `PASS` undercounts. The retained
normalized ledger extracts all 100 runner `PASS/FAIL <source-name>.lua` records.

Fresh independent **static review checkpoint:** no material transport defect has
been confirmed at this checkpoint; this is not a final acceptance or runtime
validation claim. The parent independently verified that all six probe-source
hashes match the retained 143-case run ledger. The parent's attempted independent
queued reproduction timed out at admission after 30 seconds (exit **75**), before
any payload ran; **no independent runtime reproduction is claimed**. Worker
results remain 143/143 focused oracles, 81/81 native recheck and 98/100 stable
suite cases. These report-only corrections change neither probe sources nor
retained outcomes, so their recorded source hashes remain unchanged.

Development history is not hidden or counted as final repeated qualification:
an initial Python parenthesis syntax error prevented a run; the first runnable
version had **119 pass / 1 fail**, because the oracle incorrectly expected a
**global-only** sentinel in session-local `show-environment`. It was corrected by
installing/querying a separate non-secret session marker, preserving successful
inspection/positive-target prerequisites. A subsequent intermediate run passed
136/136; an expanded predecessor passed 143/143, then the final source (with
positive parsed readiness barriers) passed **143/143 once**. One queue wait was
terminated by the command tool's 120-second limit while another project's slot
was occupied; no payload ran in that admission. A bounded queued invocation then
acquired admission normally. The short initial FD-only build/probe was a
lightweight check; all combined probes and suites used the queue.

### Remaining gates and limitations — not successful qualifications

Gate status is **OPEN**; implementation handoff is **BLOCKED**. These describe
evidence readiness, not native GitHub dependency metadata.

- **OPEN gate, BLOCKED handoff:**
  [Qualify supported Neovim terminal command semantics] and
  [Persistent terminals across Neovim and mobile clients] are not qualified by
  these controlled primitive fixtures. They do not establish the authenticated,
  identity-bound, durable sequence required by
  [Choose a fail-closed persistent workload launch boundary].
  Broker checks UID/operation and launcher checks broker PID, but exact
  server-generation/owner/context/terminal/pane/workload binding, process-start
  identity and authorization fencing are **not established**. Non-secret op/path
  tokens are not credentials. Hostile same-UID/root code is outside the guarantee.
- **OPEN evidence gate, BLOCKED handoff — startup/durability/retry integration:**
  no durable intent, one-time authorization, effect publication, reconciliation
  or enforced no-automatic-retry
  mechanism is implemented/tested here. The fixture performs one operation and
  has no retry path; this is **not evidence that future callers cannot retry**.
  Its acceptance label cannot independently satisfy
  [Choose a fail-closed persistent workload launch boundary] while those
  prerequisites are missing. No application readiness/completion/liveness or
  positive exec oracle is promised; observed synthetic workload markers establish
  only those test cases.
- **UNTESTED, broader bootstrap/isolation:** arbitrary raw config, later server
  mutation/contamination, all loader/startup variables and host loader policy,
  debug/error/core/host-audit sinks, every possible retained tmux store and secret
  deletion/zeroization. The passed seam is clean pre-exec environment construction
  on this controlled tuple, backed by the before-main LD_PRELOAD control; it is
  not a claim that clearing C main or sanitizing an already-contaminated server is
  safe. If the future protected server boundary cannot maintain these prerequisites,
  report FAIL/BLOCKED and reopen a live decision, never substitute GNU env,
  interpreter, static bootstrap, privilege or another dependency silently.
- **UNTESTED, additional transport adversaries:** wrong UID (no privilege changes),
  exact 107-byte positive socket boundary, FD/resource exhaustion, all EINTR/EPIPE
  schedules, endpoint ancestor/mount replacement, prolonged backpressure, concurrent
  peers, PID reuse and lost native-effect publication. The cap checks cover the
  **transmitted** argv/env entries; accounting of injected routing/default entries
  in a final product quota remains to be specified/qualified, not silently decided.
- **UNTESTED, additional cwd/lookup semantics:** mutations after final check or
  transient replacement/restoration may go undetected as
  [Choose a fail-closed persistent workload launch boundary] explicitly allows;
  no continuous pathname freeze. Full ancestor/mount/namespace schedules, every
  missing/empty/relative PATH arrangement, executable-path replacement races and
  every supported shell/startup-file behavior remain open. Flags came from this
  build's headers; no hardcoded universal Linux luv constants or FFI ABI is adopted.
- **UNTESTED, I/R:** actual Sess API/CLI adaptation and lifecycle/error propagation,
  shared buffers/consent, attached/reconnected embedded-client behavior, two-client
  sizing and native phone procedures, durable recovery and whole-workload
  termination. Separate gates remain **OPEN**:
  [Qualify native tmux identity and attachment safety],
  [Qualify tmux isolation and multi-client behavior],
  [Qualify crash-durable terminal recovery primitives] and
  [Investigate short-lived helper feasibility for exact workload termination].
  Older/newer Neovim/tmux, other libc/architecture and non-tmpfs crash durability
  are unqualified.

**Proposed tracker update (parent review/publication only):**
“[Qualify supported Neovim terminal command semantics] follow-up adds 143 passing
bounded C/private-socket case oracles plus a fresh 81-case stable native/PTY recheck.
Official latest stable re-resolved to v0.12.6; before-loader
clean-bootstrap/LD_PRELOAD controls and native FD/cwd/argv seams work on this
controlled tuple. Retain all original partial/negative evidence. This is not a
passed gate: exact native identity binding, durable authorization/publication,
reconciliation/no-retry, broader isolation and I/R remain OPEN. Stable repository
suite remains 98/100 on unchanged source/tests. Keep the
[Qualify supported Neovim terminal command semantics] gate **OPEN** and
[Persistent terminals across Neovim and mobile clients] handoff **BLOCKED**.
Independent static review and parent verification of all six retained source
hashes are recorded; independent queued reproduction timed out at admission
without running a payload. Complete independent review before evidence-only
publication; no independent runtime result is claimed.”

[Qualify supported Neovim terminal command semantics]: https://github.com/NnoFLy/sess.nvim/issues/36
[Persistent terminals across Neovim and mobile clients]: https://github.com/NnoFLy/sess.nvim/issues/24
[Choose a fail-closed persistent workload launch boundary]: https://github.com/NnoFLy/sess.nvim/issues/38#issuecomment-6428416860
[Define persistent terminal acceptance criteria and validation evidence]: https://github.com/NnoFLy/sess.nvim/issues/32#issuecomment-6391425573
[Qualify native tmux identity and attachment safety]: https://github.com/NnoFLy/sess.nvim/issues/33
[Qualify tmux isolation and multi-client behavior]: https://github.com/NnoFLy/sess.nvim/issues/34
[Qualify crash-durable terminal recovery primitives]: https://github.com/NnoFLy/sess.nvim/issues/35
[Investigate short-lived helper feasibility for exact workload termination]: https://github.com/NnoFLy/sess.nvim/issues/39
