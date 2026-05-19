---
description: Stop the Shannon worker. Use after a manual run or to abort. Does not delete the clone.
---

Invoke the `shannon-for-claude-code:shannon-pentester` agent in **stop mode**.

Tell the agent: "Stop only — locate the `shannon/` directory in the current working directory and run `./shannon stop` (NOT `--clean`). Do not delete the clone. Confirm worker is down and return."

User-provided arguments: $ARGUMENTS
