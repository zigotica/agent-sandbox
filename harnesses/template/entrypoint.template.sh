#!/bin/sh
# Template: Entrypoint for a new harness
#
# This is a starting point. You'll need to:
# 1. Adjust the XDG dirs if your agent uses different paths
# 2. Add any agent-specific symlinks (see opencode's entrypoint for an example)
# 3. Change the exec command at the bottom to your agent's binary name
#
# Place this file in the same directory as your Dockerfile.

set -e

# Synthesize a passwd entry for the runtime UID so tools that call
# getpwuid() can resolve the user.
if ! grep -q "^[^:]*:[^:]*:$(id -u):" /etc/passwd; then
    printf 'agentuser:x:%d:%d:agentuser:%s:/bin/sh\n' \
        "$(id -u)" "$(id -g)" "${HOME}" >> /etc/passwd
fi

# Set container-local environment.
# HOME is container-local so dotfiles don't pollute the project mount.
# AGENT_CONFIG_DIR points to the persisted config mount.
# AGENT_DATA_DIR points to the persisted data mount.
export HOME=/home/agentuser
export AGENT_CONFIG_DIR=/agent-config
export AGENT_DATA_DIR=/agent-data
export XDG_CONFIG_HOME=/home/agentuser/.config
export XDG_CACHE_HOME=/home/agentuser/.cache
export XDG_DATA_HOME=/home/agentuser/.local/share
export XDG_RUNTIME_DIR=/tmp/agent-sandbox-runtime
export TMPDIR=/tmp

mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" "${XDG_RUNTIME_DIR}"

# ──────────────────────────────────────────────────────────────────────
# Agent-specific setup goes here.
#
# If your agent stores config in XDG_CONFIG_HOME/<agent-name> and data
# in XDG_DATA_HOME/<agent-name>, symlink them to the persisted mounts
# so settings and sessions survive across runs. For example:
#
#   ln -sf /agent-config "${XDG_CONFIG_HOME}/<agent-name>"
#   ln -sf /agent-data "${XDG_DATA_HOME}/<agent-name>"
#
# If your agent uses a single directory for everything (like pi), you
# don't need symlinks — just point it at the mount directly via an
# env var in the harness script's entrypoint.
# ──────────────────────────────────────────────────────────────────────

# Replace "<agent-binary>" with your agent's command name.
exec <agent-binary> "$@"