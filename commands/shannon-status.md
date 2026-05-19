---
description: Check progress of a running Shannon scan (./shannon status + ./shannon logs).
---

Invoke the `shannon-for-claude-code:shannon-pentester` agent in **status mode**.

Tell the agent: "Status check only — do NOT clone, configure, start, or stop. Locate the `shannon/` directory in the current working directory, run `./shannon status`, and if a workspace ID is known, tail `./shannon logs <workspace>` for the latest activity. Summarize state in 3-5 lines and return."

User-provided arguments (optional workspace id): $ARGUMENTS
