---
description: Run an end-to-end Shannon pentest — clone/update Shannon, configure credentials, start the worker, wait for completion, save the report, stop the worker.
---

Invoke the `shannon-for-claude-code:shannon-pentester` agent to run the full Shannon pipeline.

Pass the user's arguments as the target hint, but the agent is responsible for confirming the target URL and the path to the repo to test via AskUserQuestion if not already supplied.

User-provided arguments (may be empty): $ARGUMENTS

Begin now.
