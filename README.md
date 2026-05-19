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

## Install

### Via marketplace (recommended)

Inside Claude Code:

```
/plugin marketplace add github.com/GamblerIX2/ShannonForClaudeCode
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
│   ├── read-env.sh
│   ├── write-env.sh
│   ├── start-shannon.sh
│   ├── save-report.sh
│   └── cleanup.sh
├── assets/
│   └── shannon-summary.md.template
├── README.md
└── LICENSE
```

## Notes on credentials

The agent does not refuse plaintext AI provider keys. This is intentional: Shannon needs them to run, you own them, and the alternative (forcing you through environment-variable gymnastics in every session) makes the plugin unusable. The agent writes the key to `./shannon/.env` with mode `0600`. It is your responsibility to keep that file out of version control — the included `.gitignore` skips both `shannon/` and `shannon-reports/`.

## Limits

- Native Windows + Docker Desktop is not supported. Use WSL2.
- The plugin does not support `./shannon stop --clean`. If you want a full Docker volume wipe, run it manually.
- Report parsing for the chat summary is best-effort markdown skimming. The on-disk markdown is the authoritative artifact.

## License

MIT — see `LICENSE`.
