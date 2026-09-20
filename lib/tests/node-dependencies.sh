#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_SANDBOX_DIR="$(cd "${TEST_DIR}/../.." && pwd)"

die() {
    echo "error: $*" >&2
    exit 1
}

# shellcheck source=../node-dependencies.sh
source "${AGENT_SANDBOX_DIR}/lib/node-dependencies.sh"

fixture_root="$(mktemp -d)"
fixture_root="$(cd "${fixture_root}" && pwd -P)"
trap 'rm -rf "${fixture_root}"' EXIT
tests_run=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    tests_run=$((tests_run + 1))
    if [[ "${expected}" != "${actual}" ]]; then
        echo "FAIL: ${message}: expected '${expected}', got '${actual}'" >&2
        exit 1
    fi
}

write_package() {
    local path="$1"
    local body="$2"
    mkdir -p "$(dirname "${path}")"
    printf '%s\n' "${body}" > "${path}"
}

single="${fixture_root}/single"
write_package "${single}/package.json" '{"devDependencies":{"vitest":"1.0.0"}}'
printf '{}\n' > "${single}/package-lock.json"
discover_node_dependencies "${single}"
assert_eq "1" "${#NODE_PACKAGE_ROOTS[@]}" "single package root"
assert_eq "npm" "${NODE_INSTALL_MANAGERS[0]}" "npm detection"

workspace="${fixture_root}/workspace project"
write_package "${workspace}/package.json" '{"workspaces":["services/*"]}'
write_package "${workspace}/services/api/package.json" '{"dependencies":{"express":"1.0.0"}}'
write_package "${workspace}/services/web/package.json" '{"devDependencies":{"vite":"1.0.0"}}'
printf 'lockfileVersion: 9\n' > "${workspace}/pnpm-lock.yaml"
discover_node_dependencies "${workspace}"
assert_eq "3" "${#NODE_PACKAGE_ROOTS[@]}" "workspace package roots"
assert_eq "1" "${#NODE_INSTALL_ROOTS[@]}" "workspace installation root"
assert_eq "pnpm" "${NODE_INSTALL_MANAGERS[0]}" "pnpm detection"
assert_eq "${workspace}" "${NODE_PACKAGE_INSTALL_ROOTS[2]}" "workspace grouping"

empty_workspace="${fixture_root}/empty-workspace"
write_package "${empty_workspace}/package.json" '{}'
write_package "${empty_workspace}/packages/empty/package.json" '{}'
write_package "${empty_workspace}/packages/used/package.json" '{"dependencies":{"a":"1.0.0"}}'
printf '{}\n' > "${empty_workspace}/package-lock.json"
discover_node_dependencies "${empty_workspace}"
assert_eq "3" "${#NODE_PACKAGE_ROOTS[@]}" "all packages inside lockfile boundary are masked"

independent="${fixture_root}/independent"
write_package "${independent}/api/package.json" '{"dependencies":{"a":"1.0.0"}}'
write_package "${independent}/web/package.json" '{"dependencies":{"b":"1.0.0"}}'
printf '{}\n' > "${independent}/api/package-lock.json"
printf '# yarn\n' > "${independent}/web/yarn.lock"
discover_node_dependencies "${independent}"
assert_eq "2" "${#NODE_INSTALL_ROOTS[@]}" "independent installation roots"
assert_eq "npm" "${NODE_INSTALL_MANAGERS[0]}" "independent npm root"
assert_eq "yarn" "${NODE_INSTALL_MANAGERS[1]}" "independent yarn root"

nested="${fixture_root}/nested"
write_package "${nested}/package.json" '{"dependencies":{"a":"1.0.0"}}'
write_package "${nested}/apps/child/package.json" '{"dependencies":{"b":"1.0.0"}}'
printf '{}\n' > "${nested}/package-lock.json"
printf '# yarn\n' > "${nested}/apps/child/yarn.lock"
discover_node_dependencies "${nested}"
assert_eq "2" "${#NODE_INSTALL_ROOTS[@]}" "nested installation boundaries"
child_install_root=""
for index in "${!NODE_PACKAGE_ROOTS[@]}"; do
    if [[ "${NODE_PACKAGE_ROOTS[$index]}" == "${nested}/apps/child" ]]; then
        child_install_root="${NODE_PACKAGE_INSTALL_ROOTS[$index]}"
    fi
done
assert_eq "${nested}/apps/child" "${child_install_root}" "nearest lockfile root"

ignored="${fixture_root}/ignored"
write_package "${ignored}/package.json" '{"dependencies":{"a":"1.0.0"}}'
write_package "${ignored}/node_modules/bad/package.json" '{"dependencies":{"bad":"1.0.0"}}'
write_package "${ignored}/dist/generated/package.json" '{"dependencies":{"bad":"1.0.0"}}'
printf '{}\n' > "${ignored}/package-lock.json"
discover_node_dependencies "${ignored}"
assert_eq "1" "${#NODE_PACKAGE_ROOTS[@]}" "ignored generated directories"

unlocked="${fixture_root}/unlocked"
write_package "${unlocked}/package.json" '{"dependencies":{"a":"1.0.0"}}'
if (discover_node_dependencies "${unlocked}" > /dev/null 2>&1); then
    echo "FAIL: package without lockfile should fail" >&2
    exit 1
fi
tests_run=$((tests_run + 1))

mixed="${fixture_root}/mixed"
write_package "${mixed}/package.json" '{"packageManager":"pnpm@10.0.0","dependencies":{"a":"1.0.0"}}'
printf '{}\n' > "${mixed}/package-lock.json"
printf 'lockfileVersion: 9\n' > "${mixed}/pnpm-lock.yaml"
discover_node_dependencies "${mixed}"
assert_eq "pnpm" "${NODE_INSTALL_MANAGERS[0]}" "packageManager resolves mixed lockfiles"

fingerprint_before="$(node_source_fingerprint "${mixed}" "${mixed}/pnpm-lock.yaml" pnpm)"
printf 'strict-peer-dependencies=true\n' > "${mixed}/.npmrc"
fingerprint_after="$(node_source_fingerprint "${mixed}" "${mixed}/pnpm-lock.yaml" pnpm)"
if [[ "${fingerprint_before}" == "${fingerprint_after}" ]]; then
    echo "FAIL: package-manager config should invalidate the fingerprint" >&2
    exit 1
fi
tests_run=$((tests_run + 1))

project_hash="$(node_dependency_project_hash "${workspace}")"
first_volume="$(node_volume_for_package "${project_hash}" "${workspace}/services/api")"
second_volume="$(node_volume_for_package "${project_hash}" "${workspace}/services/api")"
assert_eq "${first_volume}" "${second_volume}" "stable volume name"
if [[ "${first_volume}" == *' '* ]]; then
    echo "FAIL: volume name contains spaces" >&2
    exit 1
fi
tests_run=$((tests_run + 1))

echo "PASS: ${tests_run} node dependency tests"
