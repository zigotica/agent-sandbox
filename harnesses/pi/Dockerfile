FROM cgr.dev/chainguard/node:latest-dev

# Install runtime dependencies.
# The -dev base image includes git and openssh-client — we remove them.
# No git, no SSH. By design.
USER root
RUN apk del --no-cache git openssh-client 2>/dev/null || true
RUN apk add --no-cache \
        curl \
        ca-certificates \
        tmux \
        ripgrep \
        bubblewrap \
        socat

# Install pi globally.
# Defaults to latest; pin a version in config.json with {"pi": {"version": "0.66.1"}}
ARG VERSION=
RUN if [ -n "$VERSION" ]; then \
        npm install -g "@mariozechner/pi-coding-agent@${VERSION}"; \
    else \
        npm install -g "@mariozechner/pi-coding-agent"; \
    fi

# Prepend extension binaries (host-mounted via /agent-config/agent).
# Security: binaries here can shadow commands; no privilege escalation
# (--privileged, --no-new-privileges), but review installed packages.
ENV PATH="/agent-config/agent/npm-global/bin:${PATH}"

# /home/agentuser: world-writable (1777) so any runtime UID can write here.
# /etc/passwd: world-writable so the entrypoint can add the runtime UID.
RUN mkdir -p /home/agentuser \
    && chmod 1777 /home/agentuser \
    && chmod a+w /etc/passwd

ENV HOME=/home/agentuser

# Copy the pi-specific entrypoint script.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]