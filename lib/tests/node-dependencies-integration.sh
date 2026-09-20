#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SANDBOX_DIR="$(cd "${TEST_DIR}/../.." && pwd)"

# shellcheck source=../common.sh
source "${AGENT_SANDBOX_DIR}/lib/common.sh"

image="${1:-agent-sandbox:pi}"
fixture="$(mktemp -d)"
fixture="$(cd "${fixture}" && pwd -P)"

cleanup() {
    if [[ ${#NODE_PACKAGE_VOLUMES[@]} -gt 0 ]]; then
        docker volume rm "${NODE_PACKAGE_VOLUMES[@]}" > /dev/null 2>&1 || true
    fi
    rm -rf "${fixture}"
}
trap cleanup EXIT

mkdir -p "${fixture}/config" "${fixture}/data" "${fixture}/node_modules"
printf '%s\n' '{"name":"agent-sandbox-integration","version":"1.0.0"}' > "${fixture}/package.json"
printf '%s\n' '{"name":"agent-sandbox-integration","version":"1.0.0","lockfileVersion":3,"requires":true,"packages":{"":{"name":"agent-sandbox-integration","version":"1.0.0"}}}' > "${fixture}/package-lock.json"
printf 'darwin\n' > "${fixture}/node_modules/host-marker"

prepare_node_dependencies \
    "${fixture}" "${image}" "${fixture}/config" "${fixture}/data" \
    /agent-config /agent-data

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "${fixture}:${fixture}" \
    "${NODE_DEPENDENCY_DOCKER_FLAGS[@]}" \
    --workdir "${fixture}" \
    --entrypoint /bin/sh \
    "${image}" \
    -c 'test ! -e node_modules/host-marker && test -f node_modules/.agent-sandbox-dependencies.json && printf "linux\n" > node_modules/container-marker'

[[ "$(cat "${fixture}/node_modules/host-marker")" == "darwin" ]]
[[ ! -e "${fixture}/node_modules/container-marker" ]]

prepare_node_dependencies \
    "${fixture}" "${image}" "${fixture}/config" "${fixture}/data" \
    /agent-config /agent-data

echo "PASS: Linux dependency volume masks and preserves host node_modules"
