# ShannonForClaudeCode

End-to-end automation of [Shannon](https://github.com/KeygraphHQ/shannon) — a white-box AI pentester — driven from inside Claude Code. Five stages, one command: clone → configure → run → collect report → cleanup.

## What this plugin does

Adds three slash commands and one subagent to Claude Code:

| Command | What it does |
| --- | --- |
| `/shannon-run` | Full pipeline: clone-or-pull Shannon, write `.env` credentials, start the worker, wait for completion, save the markdown report to `./shannon-reports/`, stop the worker. |
| `/shannon-status` | Show progress of an in-flight scan. |
| `/shannon-stop` | Stop the Shannon worker without deleting the clone. |

All three delegate to the `shannon-for-claude-code:shannon-pentester` agent. The agent asks for any missing input (target URL, repo path, AI provider credentials) via interactive prompts.

## Requirements

| | Linux | Windows |
| --- | --- | --- |
| OS layer | bare-metal or VM Linux | **WSL2 only** (not native Windows) |
| Docker | engine via `apt`/`get.docker.com` | install inside WSL2 (not Docker Desktop for Windows) |
| Node | 18+ | 18+ inside WSL2 |
| pnpm | latest | latest |
| git | any recent | any recent |

The plugin runs `bin/preflight.sh` first and reports missing pieces with install commands.

### Running as root

Shannon itself refuses to run as the root user. The plugin handles this for you:

- **If you launch the plugin as root:** it auto-creates a service user (default name `shannon`, override with `SHANNON_USER`), adds it to the `docker` group, gives it ownership of `./shannon/`, grants it read access to your source repo (via ACL when supported, otherwise `chmod a+rX`), and re-execs Shannon under that user. Requires one of `runuser`, `sudo`, or `su` on `PATH`.
- **If you launch as a regular user:** Shannon runs as that user; no provisioning happens.

This means `/shannon-run` "just works" whether you start Claude Code as root or as a regular account.

## Install

### Via marketplace (recommended)

Inside Claude Code:

```
/plugin marketplace add GamblerIX2/ShannonForClaudeCode
/plugin install shannon-for-claude-code@shannon-for-claude-code
```

### Local development

```bash
git clone https://github.com/GamblerIX2/ShannonForClaudeCode.git
claude --plugin-dir ./ShannonForClaudeCode
```

Inside the session: `/plugin` to confirm enabled, `/agents` to see the agent listed as `shannon-for-claude-code:shannon-pentester`.

## Quick start

Open Claude Code in the directory where you want Shannon and its reports to live, then:

```
/shannon-run https://your-app.example.com /path/to/your/repo
```

You can also call it with no args — the agent will ask for the URL and repo path interactively.

The agent will:

1. Run preflight checks (Docker, Node, pnpm, git, WSL2 detection).
2. Clone `KeygraphHQ/shannon` into `./shannon/` (or `git pull` if already present), then `pnpm install && pnpm build`.
3. Check `./shannon/.env` for an AI provider credential. If none, ask you which provider (Anthropic API key, Claude Code OAuth token, AWS Bedrock, Google Vertex) and accept the value in plaintext.
4. Start the Shannon worker in the background, then watch for completion via the Monitor tool.
5. Copy the produced report to `./shannon-reports/<workspace>-<UTC-timestamp>.md` and post a chat summary with severity counts and top findings.
6. Run `./shannon stop` to release the worker (clone is kept for next time).

## Files

```
ShannonForClaudeCode/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── commands/
│   ├── shannon-run.md
│   ├── shannon-status.md
│   └── shannon-stop.md
├── agents/
│   └── shannon-pentester.md
├── bin/
│   ├── preflight.sh
│   ├── ensure-shannon.sh
│   ├── ensure-target-repo.sh
│   ├── read-env.sh
│   ├── write-env.sh
│   ├── start-shannon.sh
│   ├── save-report.sh
│   ├── cleanup.sh
│   └── with-shannon-user.sh
├── assets/
│   └── shannon-summary.md.template
├── README.md
└── LICENSE
```

## Notes on credentials

The agent does not refuse plaintext AI provider keys. This is intentional: Shannon needs them to run, you own them, and the alternative (forcing you through environment-variable gymnastics in every session) makes the plugin unusable. The agent writes the key to `./shannon/.env` with mode `0600`. It is your responsibility to keep that file out of version control — the included `.gitignore` skips both `shannon/` and `shannon-reports/`.

## Auto-initialization of the target repo (since 0.3.0)

Shannon's own preflight requires the target source tree to be a git checkout (it uses git for baseline tracking and snapshot diffs). Previously you had to `git init` the directory yourself before running `/shannon-run`. As of 0.3.0 the plugin does this for you, but only locally:

- If `<repo-path>/.git/` already exists, nothing happens.
- Otherwise `bin/ensure-target-repo.sh` runs `git init` in that directory, writes a minimal `.gitignore` (only if you don't already have one — excludes `shannon/`, `shannon-reports/`, `.shannon/`, `.env`, `node_modules/`), and creates one commit authored as `shannon-baseline <shannon@local>` with the message `shannon baseline (auto-created by ShannonForClaudeCode; local only, no remote)`.
- **No remote is ever added.** The repo stays entirely on your disk. The baseline is yours to keep, rebase, or delete.

If you'd rather control the initial commit yourself, `git init` the directory before running `/shannon-run` and the helper will no-op.

## Troubleshooting

### `Workflow FAILED — preflight failed — Not a git repository`

This should no longer happen on 0.3.0+ — the plugin auto-initializes any missing `.git/` before invoking Shannon. If you still see it, check:

1. `bin/ensure-target-repo.sh` ran and printed `initialized git repo at <path>` in your scan output.
2. The repo path you passed is the same one Shannon reports in `session.json` under `repoPath`. (Shannon bind-mounts your host path into the container as `/repos/<basename>` — same `.git` contents, different absolute path inside the container.)
3. `git` is installed on the host (`which git`).

### "Shannon must not be run as the root user"

Handled automatically — see "Running as root" above. The plugin will provision a `shannon` service user and re-exec under it.

### The agent says the run is in progress but never reports back

Since v0.2.0, `bin/start-shannon.sh` always emits a terminal marker line:

```
SHANNON_RUN_RESULT: success
SHANNON_RUN_RESULT: failed (exit=<n>) reason=<short>
```

If a run fails, the script also dumps the last 80 lines of the relevant `workflow.log` to its own stdout so the agent (and you) see the actual error without having to dig into the workspace directory. If you still see a silent hang, check `./shannon/workspaces/*/workflow.log` directly — that file is the authoritative source of failure.

## Limits

- Native Windows + Docker Desktop is not supported. Use WSL2.
- The plugin does not support `./shannon stop --clean`. If you want a full Docker volume wipe, run it manually.
- Report parsing for the chat summary is best-effort markdown skimming. The on-disk markdown is the authoritative artifact.

## License

MIT — see `LICENSE`.
