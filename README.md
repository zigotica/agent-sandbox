# agent-sandbox

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://github.com/zigotica/agent-sandbox/actions/workflows/release.yml/badge.svg)](https://github.com/zigotica/agent-sandbox/actions/workflows/release.yml)
[![Docker Base](https://img.shields.io/badge/base%20image-cgr.dev%2Fchainguard%2Fnode-blue)](https://github.com/chainguard-images/images)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-brightgreen)](https://github.com/zigotica/agent-sandbox/network/dependencies)

## What / Why

Running AI agents directly on your host gives them full access to your filesystem — SSH keys, AWS credentials, other projects, system files, etc. **agent-sandbox** runs AI coding agents (like [pi](https://github.com/badlogic/pi-mono/commits/main/packages/coding-agent) and [opencode](https://github.com/anomalyco/opencode)) inside Docker containers for security isolation, protecting your host machine from accidental or malicious actions by the agent.

This is not foolproof — no sandbox is — but it adds a meaningful layer of protection. A determined attacker with code execution could still exfiltrate data via the network or the mounted project directory. Think of it as seatbelts, not a vault.

### How it works

```
┌──────────────────────────────────────────────────────────────────┐
│                         Host Machine                             │
│                                                                  │
│  $HOME/.pi/               $HOME/my-project/                      │
│  ├── agent/                ├── src/                              │
│  ├── auth.json             ├── tests/                            │
│  └── sessions/             └── ...                               │
│        │                         │                               │
│        │ (config mount, rw)      │ (project mount, rw)           │
│        ▼                         ▼                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │              Docker Container (ephemeral)                  │  │
│  │                                                            │  │
│  │  /agent-config/      ◄─── config (rw, persisted)           │  │
│  │  /agent-data/        ◄─── data (rw, persisted)             │  │
│  │  /my-project/        ◄─── project (rw, persisted)          │  │
│  │  /home/agentuser/   ◄─── HOME (ephemeral)                  │  │
│  │                                                            │  │
│  │  πi / opencode     ◄─── runs here                          │  │
│  │  API keys            ◄─── passed from host env             │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

- **Project directory** is mounted at its real path (preserves pi's per-project sessions)
- **Config directory** (`$HOME/.pi` for pi, `$HOME/.config/opencode` for opencode) is mounted read-write so auth, sessions, and settings persist
- **Data directory** (`$HOME/.local/share/opencode` for opencode) is mounted read-write so databases and session history persist
- **HOME** is container-local — dotfiles, caches, and temp files never touch the host project
- **No git or SSH** inside the container - by design, reduces attack surface
- **`--privileged`** — required for pi's bwrap sandbox to work inside Docker (the container itself is still isolated; bwrap adds a second layer of filesystem sandboxing)
- Container is removed on exit (`--rm`)
- **Runs as your UID/GID** — files created in mounted directories are owned by you, not root

### Mount points

| Host path                                             | Container path                                | Mode | Purpose                           |
| ----------------------------------------------------- | --------------------------------------------- | ---- | --------------------------------- |
| harness config dir (e.g. `$HOME/.pi`)                 | `/agent-config`                               | rw   | Config, credentials, settings     |
| harness data dir (e.g. `$HOME/.local/share/opencode`) | `/agent-data`                                 | rw   | Sessions, databases, runtime data |
| Current working directory                             | Same real path (e.g. `/Users/you/my-project`) | rw   | Project files                     |

All other runtime files (caches, temp files) go to container-local paths under `/home/agentuser/` and are lost when the container exits.

### Why two separate mounts?

Different agents store different types of data in different locations:

- **pi** stores everything in `$HOME/.pi` — both mounts point to the same directory
- **opencode** stores config in `$HOME/.config/opencode` and data in `$HOME/.local/share/opencode` — they must be separate so settings and sessions both persist

## Requirements

- **Docker** (Docker Desktop on macOS, Docker Engine on Linux)
- **Bash** 4.0+
- **jq** (for parsing config.json)
- **Internet connection** (for pulling base images, API calls)

## Installation

### Homebrew

```bash
brew tap zigotica/tap
brew install agent-sandbox
```

Or in one command: `brew install zigotica/tap/agent-sandbox` (this ensures you get this tap's version even if `agent-sandbox` is ever added to Homebrew core).

### npm

```bash
npm install -g @zigotica/agent-sandbox
```

Installs the `agent-sandbox` binary to your npm global bin directory.

### GitHub Release

```bash
curl -fsSL https://raw.githubusercontent.com/zigotica/agent-sandbox/refs/heads/main/install.sh | bash
```

This downloads the latest release to `$HOME/.agent-sandbox` and offers to add it to your PATH.

To install a specific version:

```bash
AGENT_SANDBOX_VERSION=v1.0.0 curl -fsSL https://raw.githubusercontent.com/zigotica/agent-sandbox/refs/heads/main/install.sh | bash
```

### Manual

```bash
git clone https://github.com/zigotica/agent-sandbox.git "$HOME/.agent-sandbox"

# Add to your shell profile ($HOME/.zshrc or $HOME/.bashrc):
echo 'export PATH="$HOME/.agent-sandbox/bin:$PATH"' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

## Quick Start

```bash
# One-time setup
agent-sandbox init

# Build the pi image
agent-sandbox pi build

# Run pi in a sandboxed container
cd "$HOME/my-project"
agent-sandbox pi
```

You might eventually forget to type `agent-sandbox pi` and just type `pi`. Set up aliases so the sandboxed version always takes priority:

```bash
# Add to $HOME/.zshrc or $HOME/.bashrc
alias pi='agent-sandbox pi'
alias opencode='agent-sandbox opencode'

# If you need the unsandboxed version temporarily, use:
\pi              # bypasses the alias
command pi       # also bypasses the alias
```

This way you always get the sandboxed version by default, and the raw command is still available with a backslash prefix if you need it.

### Check everything is working

```bash
agent-sandbox doctor
```

## Configuration

Config file: `$HOME/.config/agent-sandbox/config.json` (created by `agent-sandbox init`)

```json
{
  "harnesses": {
    "opencode": {
      "config_dir": "/Users/you/.config/opencode",
      "data_dir": "/Users/you/.local/share/opencode"
    },
    "pi": {
      "config_dir": "/Users/you/.pi",
      "data_dir": "/Users/you/.pi"
    }
  }
}
```

### Version pinning

By default, harnesses install the latest version of the agent on build. To pin a specific version, add a `version` field:

```json
{
  "harnesses": {
    "opencode": {
      "config_dir": "/Users/you/.config/opencode",
      "data_dir": "/Users/you/.local/share/opencode"
    },
    "pi": {
      "config_dir": "/Users/you/.pi",
      "data_dir": "/Users/you/.pi",
      "version": "0.66.1"
    }
  }
}
```

Remove the `version` field to go back to installing latest on next build. Note: `agent-sandbox <harness> upgrade` will warn you if a version is pinned and remind you to remove it from config.json.

### Config resolution order (highest priority first)

1. **Env var** — `AGENT_SANDBOX_CONFIG_DIR=/custom/path agent-sandbox pi`
2. **config.json** — `harnesses.<name>.config_dir` / `harnesses.<name>.data_dir`
3. **Harness script default** — `HARNESS_DEFAULT_CONFIG_DIR` / `HARNESS_DEFAULT_DATA_DIR`

## Commands

```bash
agent-sandbox init                 # Create config file with sensible defaults
agent-sandbox doctor               # Check setup for problems
agent-sandbox list                 # List all registered harnesses
agent-sandbox test pi              # Run security verification tests

agent-sandbox pi build             # Build (or rebuild) the pi Docker image
agent-sandbox pi                   # Run pi in a sandboxed container
agent-sandbox pi upgrade           # Rebuild image

agent-sandbox opencode build       # Build (or rebuild) the opencode Docker image
agent-sandbox opencode             # Run opencode in a sandboxed container
agent-sandbox opencode upgrade     # Rebuild image

# Register a custom harness
agent-sandbox register aider /path/to/aider/aider.sh --config-dir "$HOME/.aider" --data-dir "$HOME/.local/share/aider"
agent-sandbox unregister aider
```

### Non-interactive usage

Pass a single prompt and exit:

```bash
agent-sandbox pi -p "summarize this repo"
```

Pipe input:

```bash
cat README.md | agent-sandbox pi -p "summarize this"
```

## Built-in Harnesses

### pi

| Setting    | Value                        |
| ---------- | ---------------------------- |
| Config dir | `$HOME/.pi`                  |
| Data dir   | `$HOME/.pi` (same as config) |
| Image      | `agent-sandbox:pi`           |
| Dockerfile | `harnesses/pi/Dockerfile`    |

Based on Chainguard Node.js. Includes: Node.js, curl, tmux, ripgrep, bubblewrap, socat, pi. No git or SSH - by design.

Installs the latest version by default. Pin a specific version in config.json if needed.

Environment variables passed through:

- AI provider keys: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `AZURE_OPENAI_API_KEY`, `MISTRAL_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`, `AI_GATEWAY_API_KEY`, `ZAI_API_KEY`, `OPENCODE_API_KEY`, `KIMI_API_KEY`, `MINIMAX_API_KEY`, `MINIMAX_CN_API_KEY`
- Ollama: `OLLAMA_API_BASE`, `OLLAMA_API_KEY`
- Pi config: `PI_SKIP_VERSION_CHECK`, `PI_CACHE_RETENTION`, `PI_PACKAGE_DIR`
- Terminal: `TERM`, `COLORTERM`

### opencode

| Setting    | Value                           |
| ---------- | ------------------------------- |
| Config dir | `$HOME/.config/opencode`        |
| Data dir   | `$HOME/.local/share/opencode`   |
| Image      | `agent-sandbox:opencode`        |
| Dockerfile | `harnesses/opencode/Dockerfile` |

Based on Chainguard Node.js. Includes: Node.js, curl, tmux, ripgrep, bubblewrap, socat, opencode-ai (via npm). No git or SSH - by design.

Installs the latest version by default. Pin a specific version in config.json if needed.

Environment variables passed through:

- AI provider keys: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `AZURE_OPENAI_API_KEY`, `MISTRAL_API_KEY`, `GROQ_API_KEY`, `CEREBRAS_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`, `AI_GATEWAY_API_KEY`
- Terminal: `TERM`, `COLORTERM`

Opencode's config (theme, models, `tui.json`) persists in `$HOME/.config/opencode`. Sessions, auth, and databases persist in `$HOME/.local/share/opencode`.

## Adding a Custom Harness

```bash
# 1. Create a harness directory with three files:
#    myagent/
#    ├── myagent.sh         # Harness script (see harnesses/template/template.sh for reference)
#    ├── Dockerfile         # Container image definition
#    └── entrypoint.sh      # Container entrypoint
#
# 2. Register it:
agent-sandbox register myagent /path/to/myagent/myagent.sh --config-dir $HOME/.config/myagent --data-dir $HOME/.local/share/myagent

# 3. Build and run:
agent-sandbox myagent build
agent-sandbox myagent
```

Each harness script must define:

- `HARNESS_NAME` — display name (used in CLI commands like `agent-sandbox cursor`)
- `HARNESS_IMAGE` — Docker image tag
- `HARNESS_DEFAULT_CONFIG_DIR` — default config directory (use `$HOME`, not `~`)
- `HARNESS_DEFAULT_DATA_DIR` — default data directory
- `HARNESS_CONFIG_MOUNT_POINT` — where config mounts in container (default: `/agent-config`)
- `HARNESS_DATA_MOUNT_POINT` — where data mounts in container (default: `/agent-data`)
- `HARNESS_DOCKERFILE` — path to Dockerfile (defaults to `harnesses/<name>/Dockerfile`)
- `HARNESS_ENV_VARS` — array of environment variable names to pass through

Version pinning works for custom harnesses too — add `"version": "1.2.3"` in config.json and the Dockerfile receives it as `--build-arg VERSION=1.2.3`.

## Security

### Security Model

Running `agent-sandbox pi` instead of `pi` directly means:

| Attack vector                          | Raw `pi`                              | `agent-sandbox pi`                        |
| -------------------------------------- | ------------------------------------- | ----------------------------------------- |
| Accidental `rm -rf /`                  | 💀 Deletes your entire home directory | ✅ Cannot reach outside the project mount |
| Agent reads `$HOME/.ssh/id_rsa`        | 💀 Full access to SSH keys            | ✅ Keys not mounted                       |
| Agent reads `$HOME/.aws/credentials`   | 💀 Full access to AWS creds           | ✅ Not accessible                         |
| Agent reads other projects             | 💀 Can see all of `$HOME/projects/`   | ✅ Only sees the mounted project          |
| Malicious command targets system files | 💀 Can modify `/etc`, `/var`, etc.    | ✅ Container filesystem is ephemeral      |
| Privilege escalation via `sudo`        | 💀 May succeed on host                | ✅ No `sudo` in container                 |
| Docker socket takeover                 | 💀 N/A                                | ✅ Docker socket not mounted              |

What the sandbox does **not** protect against:

- **Network exfiltration** — the agent has full network access (needed for API calls)
- **Project data exfiltration** — the agent can read/write everything in the mounted project
- **Config data exfiltration** — the agent can read `$HOME/.pi/agent/auth.json` (needed for auth)

### File ownership

The container runs as `--user $(id -u):$(id -g)` matching your host UID/GID. Files created in mounted directories (project, config, data) are owned by you. The container image creates `/home/agentuser` with `chmod 1777` so any UID can write there. agent-sandbox never chowns host files.

### Docker Flags

Every container run uses these flags:

```
--rm
--user $(id -u):$(id -g)
--privileged
--ipc=none
```

Why `--privileged`? Pi's internal sandbox (bwrap) requires the ability to create user namespaces and mount filesystems inside the container. Without `--privileged`, bwrap fails and pi cannot execute commands. The container is still isolated — no Docker socket is mounted, only the project and config directories are accessible, and the host filesystem is not reachable.

### Security Verification

Run the built-in security test from any directory:

```bash
agent-sandbox test pi
```

This mounts the test script from the install directory into the container — no need to copy it into your project. The test verifies: host secrets, SSH keys, cloud credentials, Docker socket, privilege escalation, network exfiltration tools, git access, filesystem boundaries (sibling directories, sensitive dirs), write access outside mounts, mount points, process visibility, and environment variable leakage.

## Development

```
$HOME/.agent-sandbox/
├── bin/
│   └── agent-sandbox               # Main CLI entry point
├── lib/
│   ├── common.sh                   # Shared functions and config resolution
│   └── tests/
│       ├── container-security.sh   # Security verification test suite
│       └── run-security-test.sh    # Test wrapper (echoes status, then runs suite)
├── harnesses/
│   ├── pi/
│   │   ├── pi.sh                   # Pi harness defaults
│   │   ├── Dockerfile              # Pi Docker image
│   │   └── entrypoint.sh           # Pi container entrypoint
│   ├── opencode/
│   │   ├── opencode.sh             # Opencode harness defaults
│   │   ├── Dockerfile              # Opencode Docker image
│   │   └── entrypoint.sh           # Opencode container entrypoint
│   └── template/
│       ├── template.sh             # Template for new harnesses
│       ├── Dockerfile.template     # Template Dockerfile
│       └── entrypoint.template.sh  # Template entrypoint
├── .github/
│   └── workflows/
│       └── release.yml             # CI: auto-publish GitHub Releases on tag push
├── install.sh                      # Install script (curl | bash)
├── DESIGN.md
├── LICENSE
└── README.md                       # This file
```

User-created files (not in the repo):

```
$HOME/.config/agent-sandbox/
└── config.json                     # User configuration (created by agent-sandbox init)
```

## Troubleshooting

### docker: command not found

Install Docker: https://docs.docker.com/get-docker/

### jq: command not found

Install jq: https://jqlang.github.io/jq/

### Config file not found

Run `agent-sandbox init` to create the config file.

### Image not found

Images are auto-built on first run. You can also build manually:

```bash
agent-sandbox pi build
agent-sandbox opencode build
```

### Pi can't run commands (bwrap errors)

Pi's sandbox (bwrap) requires `--privileged` to create user namespaces inside Docker. This is already configured by default. If you see bwrap errors, make sure you're not overriding the Docker flags.

### Cleaning up bwrap artifacts

If bwrap creates files in your project directory (empty `.bashrc`, `.env`, `.claude`, etc.), remove them:

```bash
rm -rf .claude .env .bashrc .bash_profile .profile .zshrc .zprofile .gitconfig .gitmodules .mcp.json .ripgreprc .vscode .idea "*.key" "*.pem"
```

These are placeholder files created by the sandbox extension. Consider removing the sandbox extension since Docker already provides isolation:

```bash
rm -rf "$HOME/.pi/agent/extensions/sandbox"
rm -f "$HOME/.pi/agent/sandbox.json"
```

## Inspiration

This project was inspired by three approaches to running AI coding agents safely:

### Pi's official sandbox extension

Pi offers an [optional sandbox extension](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent/examples/extensions/sandbox) that uses bwrap to isolate the agent's file access on the host. Users install it if they want sandboxing. When running pi directly on the host, this works well. However, when you try to run pi **inside a Docker container** with the sandbox extension active, bwrap creates placeholder dotfiles (`.bashrc`, `.env`, `.claude`, `.gitconfig`, etc.) in the project directory on the host mount — polluting your repo. It also only works for pi.

### Daytona's opencode plugin

Daytona offers an [opencode plugin](https://github.com/daytonaio/daytona/tree/main/libs/opencode-plugin) that sandboxes each session in its own remote environment, synced to a local git branch. This means git is central to the isolation model — each session gets its own branch, and changes flow through git. That approach gives you version control as a safety net, but it also means git is available inside the sandbox, and the agent can push to remotes. If you don't want your agent touching git, this doesn't help.

### pi-less-yolo

[pi-less-yolo](https://github.com/cjermain/pi-less-yolo) is a Docker-based sandbox for running pi without its built-in bwrap sandbox. It takes the approach of disabling bwrap entirely (`--no-sandbox`), relying solely on Docker for isolation. While simpler, this loses the second layer of sandboxing that bwrap provides. It also only supports pi.

agent-sandbox takes a different approach:

- **No project pollution** — bwrap runs inside the container, so its placeholder files stay in the ephemeral container filesystem and never reach the host
- **No `--no-sandbox`** — bwrap stays active, providing a second layer of isolation inside the container
- **No git or SSH** — by design, the container has neither. If you want git, run it on the host
- **Works for any agent** — the same Docker-based approach works for pi, opencode, and any agent you register

## License

[MIT](LICENSE)
