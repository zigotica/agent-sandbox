#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../common.sh
source "${SOURCE_ROOT}/lib/common.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "${fixture}"' EXIT

assert_version() {
    local expected="$1"
    local actual
    actual="$(get_agent_sandbox_version)"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "FAIL: expected version '${expected}', got '${actual}'" >&2
        exit 1
    fi
}

# shellcheck disable=SC2034 # Read by get_agent_sandbox_version from common.sh.
AGENT_SANDBOX_DIR="${fixture}"
printf 'v3.2.1\n' > "${fixture}/VERSION"
assert_version "3.2.1"

rm "${fixture}/VERSION"
printf '{"version":"4.5.6"}\n' > "${fixture}/package.json"
assert_version "4.5.6"

# shellcheck disable=SC2034 # Read by get_agent_sandbox_version from common.sh.
AGENT_SANDBOX_DIR="/opt/homebrew/Cellar/agent-sandbox/7.8.9/libexec"
assert_version "7.8.9"

echo "PASS: agent-sandbox version resolution"
