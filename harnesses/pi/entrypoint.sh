#!/bin/sh
set -e

# Synthesize a passwd entry for the runtime UID so tools that call
# getpwuid() can resolve the user.
if ! grep -q "^[^:]*:[^:]*:$(id -u):" /etc/passwd; then
    printf 'agentuser:x:%d:%d:agentuser:%s:/bin/sh\n' \
        "$(id -u)" "$(id -g)" "${HOME}" >> /etc/passwd
fi

# Set container-local environment.
# HOME is container-local so dotfiles (.claude, etc.) don't pollute the
# project mount. AGENT_CONFIG_DIR and AGENT_DATA_DIR point to the persisted
# mounts. For pi, config and data live in the same host directory, so both
# mounts show the same content. PI_CODING_AGENT_DIR points to the
# agent subdirectory within the config mount.
export HOME=/home/agentuser
export AGENT_CONFIG_DIR=/agent-config
export AGENT_DATA_DIR=/agent-data
export PI_CODING_AGENT_DIR=/agent-config/agent
export XDG_CONFIG_HOME=/home/agentuser/.config
export XDG_CACHE_HOME=/home/agentuser/.cache
export XDG_RUNTIME_DIR=/tmp/agent-sandbox-runtime
export TMPDIR=/tmp

mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${XDG_RUNTIME_DIR}"

# Ensure npm global installs go to the persisted config directory.
mkdir -p /agent-config/agent/npm-global
echo "prefix=/agent-config/agent/npm-global" > /home/agentuser/.npmrc

# Run pi directly unless Herdr was explicitly requested.
if [ "${1:-}" != "--herdr" ]; then
    exec pi "$@"
fi
shift

# Herdr launches its initial pane from $SHELL; it does not accept a command
# as a positional argument. Generate a shell executable that starts pi while
# preserving remaining arguments passed through agent-sandbox.
PI_LAUNCHER="${XDG_RUNTIME_DIR}/pi-shell"
{
    printf '#!/bin/sh\nif [ "${PI_SUBAGENT_SHELL:-}" = "1" ]; then\n    exec /bin/sh\nfi\nexec pi'
    for arg in "$@"; do
        escaped=$(printf '%s' "$arg" | sed "s/'/'\\\\''/g")
        printf " '%s'" "$escaped"
    done
    printf '\n'
} > "${PI_LAUNCHER}"
chmod +x "${PI_LAUNCHER}"
export SHELL="${PI_LAUNCHER}"

# Launch Herdr using its default persistent-session behavior.
exec herdr
