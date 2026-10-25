# Stable Neovim terminal command semantics — research evidence

**Question:** [#36](https://github.com/NnoFLy/sess.nvim/issues/36).
**Collected:** 2026-10-25 UTC. **Branch:** `research/persistent-terminal-neovim-semantics`.
**Base:** `eee53cca450a1e1a64e47ebe43f507fe85669dd0`.
**Immutable evidence commit:** [`c3ea886fdd6422c62b0847ed2082393d7efdc347`](https://github.com/NnoFLy/sess.nvim/tree/c3ea886fdd6422c62b0847ed2082393d7efdc347/docs/research).
That commit contains the exact probes and ledger; this publication note alone was added afterward.

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
  workload argv/`pane_start_command`. The probe checks the retained command only
  for the synthetic value's absence. General environment-difference enumeration,
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
- [`native.lua`](probes/neovim-semantics/native.lua): only native Ex/job/window probes.
- [`fixture.py`](probes/neovim-semantics/fixture.py): synthetic argv/cwd/PTY recorder;
  allowlisted synthetic env values only, atomic result-file publication and readiness.

```sh
python3 docs/research/probes/neovim-semantics/run.py
stylua --check docs/research/probes/neovim-semantics/native.lua
NVIM_BIN=/usr/bin/nvim sh tests/run.sh
```

Final probe revision: **77 pass, 0 fail**, three independent runs: **231 checks**.
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

- **pass:** final 77-case probe, repeated three times; changed-Lua StyLua check;
  Python AST parsing; `git diff --check`.
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

## Per-case evidence ledger

Final run, sanitized. Each row has an explicit status; for a pass, the displayed
value is **both expected and observed** (the probe prints both independently).
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
| `TMUX-e-not-in-workload-command` | **pass** | `false` |
| `TMUX-e-plus-env-u-fresh-values-and-removal` | **pass** | `[null, "fresh-with-unset", []]` |
| `TMUX-e-plus-env-u-no-assignment-in-command` | **pass** | `false` |
| `TMUX-env-i-second-invocation-fresh` | **pass** | `[0, {"PROBE_VALUE": "second-invoker"}]` |
| `TMUX-real-shell-pipeline` | **pass** | `"synthetic-pipe"` |
| `TMUX-empty-command-is-no-process-negative-control` | **pass** | `"&#124;0"` |
| `TMUX-one-argument-accepted-not-direct` | **pass** | `0` |
| `TMUX-one-argument-shell-parse-negative-control` | **pass** | `["1", false]` |
