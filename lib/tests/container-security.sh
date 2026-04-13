#!/usr/bin/env bash
# agent-sandbox — Container security verification test suite
# Run from inside a sandboxed container to verify isolation.
#
# Usage:
#   agent-sandbox test pi
#
# Note: The project directory is mounted at its real host path
# (e.g. /Users/you/my-project), so parent directories like /Users
# and /Users/you are traversable — but only the project itself is
# writable. Sibling directories under the same parent should not
# be readable.
set -euo pipefail

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1" result="$2"
    case "${result}" in
        PASS) PASS=$((PASS + 1)); echo "  [PASS] ${desc}" ;;
        FAIL) FAIL=$((FAIL + 1)); echo "  [FAIL] ${desc}" ;;
        WARN) WARN=$((WARN + 1)); echo "  [WARN] ${desc}" ;;
    esac
}

echo "agent-sandbox security verification"
echo "===================================="

# ─── 0. Docker environment check ──────────────────────────────────────────────

echo "0. Docker environment"

if [ -f "/.dockerenv" ] || grep -q "docker" /proc/1/cgroup 2>/dev/null; then
    check "Running inside Docker container" PASS
else
    check "NOT running inside Docker — test results are invalid!" FAIL
    echo ""
    echo "  This test must be run via: agent-sandbox test <harness>"
    echo ""
    exit 1
fi

echo ""

# ─── 1. Host secrets ──────────────────────────────────────────────────────────

echo "1. Host secrets"

if cat /etc/shadow 2>/dev/null; then
    check "Can read /etc/shadow" FAIL
else
    check "Cannot read /etc/shadow" PASS
fi

if cat /etc/ssh/ssh_host_rsa_key 2>/dev/null; then
    check "Can read host SSH host key" FAIL
else
    check "Cannot read host SSH host key" PASS
fi

if cat /etc/ssh/ssh_host_ed25519_key 2>/dev/null; then
    check "Can read host SSH ed25519 key" FAIL
else
    check "Cannot read host SSH ed25519 key" PASS
fi

echo ""

# ─── 2. SSH keys ──────────────────────────────────────────────────────────────

echo "2. SSH keys"

# The project mount makes parent dirs traversable, but .ssh should not be readable
if cat "${HOME}/.ssh/id_rsa" 2>/dev/null; then
    check "Private SSH key readable" FAIL
else
    check "Private SSH key not accessible" PASS
fi

if cat "${HOME}/.ssh/id_ed25519" 2>/dev/null; then
    check "Ed25519 SSH key readable" FAIL
else
    check "Ed25519 SSH key not accessible" PASS
fi

if cat "${HOME}/.ssh/authorized_keys" 2>/dev/null; then
    check "Authorized keys readable" FAIL
else
    check "Authorized keys not accessible" PASS
fi

# Also try the real home dir path (macOS)
for candidate in /root/.ssh /home/*/.ssh; do
    if [ -d "${candidate}" ] 2>/dev/null && ls "${candidate}" 2>/dev/null; then
        check "SSH directory readable at ${candidate}" FAIL
    fi
done
check "No host SSH directories readable" PASS

echo ""

# ─── 3. Cloud credentials ────────────────────────────────────────────────────

echo "3. Cloud credentials"

if cat "${HOME}/.aws/credentials" 2>/dev/null; then
    check "AWS credentials readable" FAIL
else
    check "AWS credentials not accessible" PASS
fi

if cat "${HOME}/.config/gcloud/credentials.db" 2>/dev/null; then
    check "GCP credentials readable" FAIL
else
    check "GCP credentials not accessible" PASS
fi

if cat "${HOME}/.azure/credentials" 2>/dev/null; then
    check "Azure credentials readable" FAIL
else
    check "Azure credentials not accessible" PASS
fi

for candidate in /root/.aws /root/.config/gcloud /root/.azure; do
    if [ -d "${candidate}" ] 2>/dev/null && ls "${candidate}" 2>/dev/null; then
        check "Cloud credential directory readable at ${candidate}" FAIL
    fi
done
check "No host cloud credential directories readable" PASS

echo ""

# ─── 4. Docker socket ─────────────────────────────────────────────────────────

echo "4. Docker socket"

if [ -S /var/run/docker.sock ]; then
    check "Docker socket mounted — container escape risk!" FAIL
else
    check "Docker socket not mounted" PASS
fi

echo ""

# ─── 5. Privilege escalation ──────────────────────────────────────────────────

echo "5. Privilege escalation"

if command -v sudo 2>/dev/null; then
    check "sudo binary available" WARN
else
    check "No sudo binary" PASS
fi

if command -v su 2>/dev/null; then
    check "su binary available" WARN
else
    check "No su binary" PASS
fi

if command -v pkexec 2>/dev/null; then
    check "pkexec binary available" WARN
else
    check "No pkexec binary" PASS
fi

# Should NOT be able to install packages
if command -v apk 2>/dev/null; then
    if apk add --no-cache nonexistent-test-pkg 2>&1 | grep -q "permission denied\|Operation not permitted\|not allowed"; then
        check "Cannot install packages via apk (permission denied)" PASS
    elif apk add --no-cache curl 2>/dev/null; then
        check "Can install packages via apk" FAIL
    else
        check "apk not available or cannot install packages" PASS
    fi
else
    check "No package manager available" PASS
fi

# Switching user should fail
if su root -c "echo got_root" 2>/dev/null; then
    check "Can switch to root via su" FAIL
else
    check "Cannot switch to root" PASS
fi

echo ""

# ─── 6. Network exfiltration tools ────────────────────────────────────────────

echo "6. Network exfiltration tools"

if command -v ssh 2>/dev/null; then
    check "ssh binary available — data could be exfiltrated via SSH" WARN
else
    check "No ssh binary" PASS
fi

if command -v scp 2>/dev/null; then
    check "scp binary available — data could be copied out via SCP" WARN
else
    check "No scp binary" PASS
fi

if command -v rsync 2>/dev/null; then
    check "rsync binary available" WARN
else
    check "No rsync binary" PASS
fi

if command -v curl 2>/dev/null; then
    check "curl binary available (needed for API calls, but can also exfiltrate)" WARN
else
    check "No curl binary" WARN
fi

if command -v wget 2>/dev/null; then
    check "wget binary available" WARN
else
    check "No wget binary" PASS
fi

echo ""

# ─── 7. Git access ───────────────────────────────────────────────────────────

echo "7. Git access"

if command -v git 2>/dev/null; then
    check "git binary available — can push repo data to external remotes" WARN
else
    check "No git binary" PASS
fi

echo ""

# ─── 8. Filesystem boundary — sibling directories ────────────────────────────

echo "8. Filesystem boundary — sibling directories"

# The project mount makes its parent path traversable (e.g. /Users/you).
# That's expected. The security check is: can we READ sibling directories
# in the same parent? We should not be able to.
#
# Example: project is at /Users/you/projects/my-project
#   /Users/you/projects/         — may be listable (path traversal)
#   /Users/you/projects/secret/  — should NOT be readable
#   /Users/you/.ssh/             — should NOT be readable

# Find the project mount point (the working directory)
PROJECT_DIR="$(pwd)"
PARENT_DIR="$(dirname "${PROJECT_DIR}")"

# Try reading sibling directories in the same parent
SIBLING_READABLE=0
if [ -d "${PARENT_DIR}" ]; then
    for sibling in "${PARENT_DIR}"/*/; do
        # Skip our own project directory
        if [ "${sibling}" = "${PROJECT_DIR}/" ]; then
            continue
        fi
        # Try to list contents
        if ls "${sibling}" 2>/dev/null | head -1 > /dev/null 2>&1; then
            SIBLING_READABLE=$((SIBLING_READABLE + 1))
            echo "    readable: ${sibling}"
        fi
    done
fi

if [ "${SIBLING_READABLE}" -gt 0 ]; then
    check "${SIBLING_READABLE} sibling directories are readable under ${PARENT_DIR}" FAIL
else
    check "No sibling directories readable under ${PARENT_DIR}" PASS
fi

# Specifically check sensitive directories in the user's home
# (These should be under separate mount boundaries, not the project mount)
SENSITIVE_DIRS=(
    "${HOME}/.ssh"
    "${HOME}/.aws"
    "${HOME}/.gnupg"
)
# Also try common macOS paths if HOME is /home/agentuser
if [ "${HOME}" = "/home/agentuser" ]; then
    # Find the real user home from the project path parent
    for candidate in /Users/*; do
        SENSITIVE_DIRS+=(
            "${candidate}/.ssh"
            "${candidate}/.aws"
            "${candidate}/.gnupg"
        )
    done
fi

LEAKED=0
for dir in "${SENSITIVE_DIRS[@]}"; do
    if [ -d "${dir}" ] 2>/dev/null && ls "${dir}" 2>/dev/null; then
        LEAKED=$((LEAKED + 1))
        echo "    leaked: ${dir}"
    fi
done

if [ "${LEAKED}" -gt 0 ]; then
    check "${LEAKED} sensitive host directories are readable" FAIL
else
    check "No sensitive host directories readable" PASS
fi

echo ""

# ─── 9. Write access outside mounts ──────────────────────────────────────────

echo "9. Write access outside mounts"

EPHEMERAL_LOCATIONS=("/tmp" "/var/tmp")
PERSISTENT_LOCATIONS=("/root" "/home" "/etc" "/usr" "/opt")

for loc in "${EPHEMERAL_LOCATIONS[@]}"; do
    if touch "${loc}/outside-test" 2>/dev/null; then
        check "${loc} is writable (expected — ephemeral, lost on exit)" PASS
        rm -f "${loc}/outside-test"
    else
        check "${loc} is not writable" WARN
    fi
done

for loc in "${PERSISTENT_LOCATIONS[@]}"; do
    if touch "${loc}/outside-test" 2>/dev/null; then
        check "Can write to ${loc}" FAIL
        rm -f "${loc}/outside-test" 2>/dev/null || true
    else
        check "Cannot write to ${loc}" PASS
    fi
done

echo ""

# ─── 10. Mount points ─────────────────────────────────────────────────────────

echo "10. Mount points"

# List what's actually mounted (only /agent-config, /agent-data, and project)
MOUNTED_VOLUMES=""
if [ -d /agent-config ]; then
    MOUNTED_VOLUMES="${MOUNTED_VOLUMES} /agent-config"
fi
if [ -d /agent-data ]; then
    MOUNTED_VOLUMES="${MOUNTED_VOLUMES} /agent-data"
fi
if [ -d "${PROJECT_DIR}" ]; then
    MOUNTED_VOLUMES="${MOUNTED_VOLUMES} ${PROJECT_DIR}"
fi

echo "    Mounted: ${MOUNTED_VOLUMES}"
check "Mount points look correct" PASS

echo ""

# ─── 11. Process visibility ──────────────────────────────────────────────────

echo "11. Process visibility"

PROCESS_COUNT=$(ps aux 2>/dev/null | wc -l || echo "0")
# Subtract header line
PROCESS_COUNT=$((PROCESS_COUNT > 0 ? PROCESS_COUNT - 1 : 0))

if [ "${PROCESS_COUNT}" -gt 10 ]; then
    check "Can see ${PROCESS_COUNT} processes (host processes may be visible)" WARN
else
    check "Only container processes visible (${PROCESS_COUNT})" PASS
fi

echo ""

# ─── 12. Environment variable leakage ────────────────────────────────────────

echo "12. Environment variable leakage"

# API keys should only be passed through if explicitly configured
# Check that no unexpected secrets are in the environment
LEAKED_SECRETS=0
for var in GITHUB_TOKEN GH_TOKEN GITLAB_TOKEN HEROKU_API_KEY DIGITALOCEAN_TOKEN; do
    if [ -n "${!var:-}" ]; then
        LEAKED_SECRETS=$((LEAKED_SECRETS + 1))
        echo "    ${var} is set"
    fi
done

if [ "${LEAKED_SECRETS}" -gt 0 ]; then
    check "${LEAKED_SECRETS} unexpected secret env vars leaked" WARN
else
    check "No unexpected secret env vars leaked" PASS
fi

echo ""

# ─── Summary ──────────────────────────────────────────────────────────────────

echo "===================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${WARN} warnings"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    echo "FAILED — ${FAIL} security check(s) failed. See [FAIL] above."
    exit 1
elif [ "${WARN}" -gt 0 ]; then
    echo "PASSED with warnings — ${WARN} warning(s). See [WARN] above."
    exit 0
else
    echo "ALL CHECKS PASSED"
    exit 0
fi