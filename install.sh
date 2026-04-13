#!/usr/bin/env bash
# agent-sandbox — Install script
# Usage: curl -fsSL https://raw.githubusercontent.com/zigotica/agent-sandbox/refs/heads/main/install.sh | bash
set -euo pipefail

REPO="zigotica/agent-sandbox"
INSTALL_DIR="${AGENT_SANDBOX_DIR:-$HOME/.agent-sandbox}"
BRANCH="${AGENT_SANDBOX_BRANCH:-main}"

echo "agent-sandbox installer"
echo "======================="
echo ""

# ─── Dependencies ─────────────────────────────────────────────────────────────

for cmd in curl tar; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "error: $cmd is required but not found" >&2
        exit 1
    fi
done

# ─── Determine version ────────────────────────────────────────────────────────

if [ -n "${AGENT_SANDBOX_VERSION:-}" ]; then
    # Explicit version override
    VERSION="${AGENT_SANDBOX_VERSION}"
    echo "Installing version: ${VERSION}"
    DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz"
elif [ "${BRANCH}" != "main" ]; then
    # Branch override (for testing)
    echo "Installing from branch: ${BRANCH}"
    DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
else
    # Find latest release via GitHub API
    echo "Finding latest release..."
    LATEST_URL="https://api.github.com/repos/${REPO}/releases/latest"
    VERSION=$(curl -fsSL "${LATEST_URL}" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "${VERSION}" ]; then
        # No releases yet, fall back to main branch
        echo "No releases found, installing from main branch"
        DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/heads/main.tar.gz"
    else
        echo "Latest release: ${VERSION}"
        DOWNLOAD_URL="https://github.com/${REPO}/archive/refs/tags/${VERSION}.tar.gz"
    fi
fi

# ─── Download and install ─────────────────────────────────────────────────────

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

echo "Downloading..."
curl -fsSL "${DOWNLOAD_URL}" -o "${TMPDIR}/agent-sandbox.tar.gz"

echo "Installing to ${INSTALL_DIR}..."

# Extract (strip top-level directory from archive)
mkdir -p "${INSTALL_DIR}"
tar -xzf "${TMPDIR}/agent-sandbox.tar.gz" -C "${INSTALL_DIR}" --strip-components=1

# Make binaries executable
chmod +x "${INSTALL_DIR}/bin/agent-sandbox"
chmod +x "${INSTALL_DIR}/lib/tests/run-security-test.sh" 2>/dev/null || true
chmod +x "${INSTALL_DIR}/lib/tests/container-security.sh" 2>/dev/null || true

echo ""
echo "Installed successfully!"
echo ""

# ─── PATH setup ───────────────────────────────────────────────────────────────

SHELL_RC=""
if [ -n "${ZSH_VERSION:-}" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if echo "${PATH}" | grep -q "${INSTALL_DIR}/bin"; then
    echo "Already in PATH."
else
    echo "Add to your shell profile to use agent-sandbox:"
    echo ""
    echo "  export PATH=\"${INSTALL_DIR}/bin:\$PATH\""
    echo ""

    if [ -n "${SHELL_RC}" ]; then
        read -rp "Add this to ${SHELL_RC}? [Y/n] " REPLY 2>/dev/null || REPLY="y"
        if [ "${REPLY}" != "n" ] && [ "${REPLY}" != "N" ]; then
            echo "" >> "${SHELL_RC}"
            echo "# agent-sandbox" >> "${SHELL_RC}"
            echo "export PATH=\"${INSTALL_DIR}/bin:\$PATH\"" >> "${SHELL_RC}"
            echo "Added to ${SHELL_RC}. Restart your shell or run:"
            echo ""
            echo "  source ${SHELL_RC}"
        fi
    fi
fi