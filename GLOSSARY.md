# Session contexts

Sess.nvim manages independent editing contexts for projects and working directories. These terms distinguish saved contexts, contexts in use, and the context currently visible in the editor.

## Language

**Session**:
An editing context associated with a project or working directory, including the editor state needed to return to it.

**Saved session**:
A session retained for later use. Being saved does not mean the session is active.

**Active session**:
A session loaded into the running editor instance and available to switch to without unloading the other active sessions.
_Avoid_: Loaded session

**Current session**:
The active session whose editing context is currently visible. Other sessions may remain active while it is current.
_Avoid_: Current project

**Session snapshot**:
The saved editor state of one session. It does not promise to preserve live processes or every runtime object.

**Resume state**:
The remembered active-session set, its order, and the current-session selection from a previous editor instance. It describes which contexts to resume, rather than containing their editor state.
_Avoid_: All saved sessions, whole-editor snapshot
