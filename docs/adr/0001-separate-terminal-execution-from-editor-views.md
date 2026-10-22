---
status: accepted
---

# Separate persistent terminal execution from editor views

Explicit launch and independent editor views are implemented by [issue #15](https://github.com/nnofly/sess.nvim/issues/15). Inventory reconciliation, automatic view restoration, remote collection, and full destructive controls remain deferred; [issue #14](https://github.com/nnofly/sess.nvim/issues/14) records the agreed feature contract.

Use an isolated tmux server to own persistent shells, agents, and commands. Neovim owns their attachment views, not their process lifetime. Unlike ordinary Neovim terminal jobs, these executions survive closing views, unloading sessions, and quitting Neovim. Keeping direct terminal-job ownership would preserve simpler teardown but would not support continued remote interaction with the same work after editor exit.

Give each sess session an owning tmux session, with one window per persistent terminal. Internal one-window attachment sessions link those windows so remote navigation cannot retarget Neovim buffers. An aggregate remote collection links the same work; it does not duplicate processes. Terminals created without a current sess session are unassigned. Ownership is independent of layout membership.

Verified tmux inventory determines which terminals exist, including windows created or closed while Neovim was absent. Session snapshots remember views and never replay launch commands. Reconciliation preserves the existing remembered-active-set resume contract rather than activating every owner with surviving work. Backend unavailability is not evidence of deletion. This separation requires independent terminal identity and reconciliation instead of persisting the existing buffer-based agent registrations.
