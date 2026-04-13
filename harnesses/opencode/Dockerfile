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

# Install opencode via npm.
# Defaults to latest; pin a version in config.json with {"opencode": {"version": "1.4.3"}}
ARG VERSION=
RUN if [ -n "$VERSION" ]; then \
        npm install -g "opencode-ai@${VERSION}"; \
    else \
        npm install -g "opencode-ai"; \
    fi

# Prepend extension binaries (host-mounted via /agent-config).
ENV PATH="/agent-config/bin:${PATH}"

# /home/agentuser: world-writable (1777) so any runtime UID can write here.
# /etc/passwd: world-writable so the entrypoint can add the runtime UID.
RUN mkdir -p /home/agentuser \
    && chmod 1777 /home/agentuser \
    && chmod a+w /etc/passwd

ENV HOME=/home/agentuser

# Copy the opencode-specific entrypoint script.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]