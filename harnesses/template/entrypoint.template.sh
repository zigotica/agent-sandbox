#!/bin/sh
# Template: Entrypoint for scaffolded harness
#
# Adjust XDG dirs and exec command for your agent.
# Add agent-specific symlinks if needed.

set -e

# Synthesize passwd entry for runtime UID so tools that call
# getpwuid() can resolve user.
if ! grep -q "^[^:]*:[^:]*:$(id -u):" /etc/passwd; then
    printf 'agentuser:x:%d:%d:agentuser:%s:/bin/sh\n' \
        "$(id -u)" "$(id -g)" "${HOME}" >> /etc/passwd
fi

# Set container-local environment.
# HOME is container-local so dotfiles don't pollute project mount.
# AGENT_CONFIG_DIR points to persisted config mount.
# AGENT_DATA_DIR points to persisted data mount.
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
# If agent stores config in XDG_CONFIG_HOME/<agent-name> and data
# in XDG_DATA_HOME/<agent-name>, symlink them to persisted mounts.
# If agent uses one dir for everything, point it at mount directly.
# ──────────────────────────────────────────────────────────────────────

# Replace "<agent-binary>" with agent command name.
exec <agent-binary> "$@"