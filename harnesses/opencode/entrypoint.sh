#!/bin/sh
set -e

# Synthesize a passwd entry for the runtime UID so tools that call
# getpwuid() can resolve the user.
if ! grep -q "^[^:]*:[^:]*:$(id -u):" /etc/passwd; then
    printf 'agentuser:x:%d:%d:agentuser:%s:/bin/sh\n' \
        "$(id -u)" "$(id -g)" "${HOME}" >> /etc/passwd
fi

# Set container-local environment.
# HOME is container-local so dotfiles don't pollute the project mount.
# AGENT_CONFIG_DIR points to the persisted config mount (opencode.json, tui.json).
# AGENT_DATA_DIR points to the persisted data mount (sessions, DB, auth).
# XDG dirs are container-local so temp files stay out of /workspace.
export HOME=/home/agentuser
export AGENT_CONFIG_DIR=/agent-config
export AGENT_DATA_DIR=/agent-data
export XDG_CONFIG_HOME=/home/agentuser/.config
export XDG_CACHE_HOME=/home/agentuser/.cache
export XDG_DATA_HOME=/home/agentuser/.local/share
export XDG_RUNTIME_DIR=/tmp/agent-sandbox-runtime
export TMPDIR=/tmp

mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_DATA_HOME}" "${XDG_RUNTIME_DIR}"

# Symlink opencode's config and data dirs to the persisted mounts
# so settings, auth, sessions, and databases survive across runs.
ln -sf /agent-config "${XDG_CONFIG_HOME}/opencode"
ln -sf /agent-data "${XDG_DATA_HOME}/opencode"

# Ensure npm global installs go to the persisted config
mkdir -p /agent-config/bin
echo "prefix=/agent-config" > /home/agentuser/.npmrc

exec opencode "$@"