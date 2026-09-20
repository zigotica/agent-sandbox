#!/bin/sh
set -eu

manager="$1"
source_fingerprint="$2"
image_id="$3"
sentinel_root="$4"
sentinel="${sentinel_root}/.agent-sandbox-dependencies.json"

if ! command -v node > /dev/null 2>&1; then
    echo "error: node is not available in the harness image" >&2
    exit 1
fi

case "${manager}" in
    npm)
        if ! command -v npm > /dev/null 2>&1; then
            echo "error: npm is not available in the harness image" >&2
            exit 1
        fi
        manager_version="$(npm --version)"
        install_label="npm ci"
        ;;
    pnpm)
        if command -v pnpm > /dev/null 2>&1; then
            manager_version="$(pnpm --version)"
            install_label="pnpm install --frozen-lockfile --dangerously-allow-all-builds"
        elif command -v corepack > /dev/null 2>&1; then
            manager_version="$(corepack pnpm --version)"
            install_label="corepack pnpm install --frozen-lockfile --dangerously-allow-all-builds"
        else
            echo "error: pnpm and corepack are not available in the harness image" >&2
            exit 1
        fi
        ;;
    yarn)
        if command -v yarn > /dev/null 2>&1; then
            manager_version="$(yarn --version)"
            install_label="yarn install --immutable"
        elif command -v corepack > /dev/null 2>&1; then
            manager_version="$(corepack yarn --version)"
            install_label="corepack yarn install --immutable"
        else
            echo "error: yarn and corepack are not available in the harness image" >&2
            exit 1
        fi
        ;;
    bun)
        if ! command -v bun > /dev/null 2>&1; then
            echo "error: bun is not available in the harness image" >&2
            exit 1
        fi
        manager_version="$(bun --version)"
        install_label="bun install --frozen-lockfile"
        ;;
    *)
        echo "error: unsupported package manager: ${manager}" >&2
        exit 1
        ;;
esac

node_version="$(node --version)"
node_abi="$(node -p 'process.versions.modules || "unknown"')"
platform="$(uname -s)-$(uname -m)"

if [ -f "${sentinel}" ] && node -e '
const fs = require("fs");
const [file, source, image, manager, managerVersion, nodeVersion, abi, platform] = process.argv.slice(1);
try {
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  process.exit(data.source === source && data.image === image && data.manager === manager &&
    data.managerVersion === managerVersion && data.nodeVersion === nodeVersion &&
    data.nodeAbi === abi && data.platform === platform ? 0 : 1);
} catch { process.exit(1); }
' "${sentinel}" "${source_fingerprint}" "${image_id}" "${manager}" "${manager_version}" "${node_version}" "${node_abi}" "${platform}"; then
    echo "    cache valid"
    exit 0
fi

echo "    running ${install_label}"
rm -f "${sentinel}"
case "${manager}" in
    npm) npm ci ;;
    pnpm)
        pnpm_store="${sentinel_root}/.pnpm-store"
        if command -v pnpm > /dev/null 2>&1; then
            pnpm install --frozen-lockfile --dangerously-allow-all-builds --store-dir "${pnpm_store}"
        else
            corepack pnpm install --frozen-lockfile --dangerously-allow-all-builds --store-dir "${pnpm_store}"
        fi
        ;;
    yarn)
        if command -v yarn > /dev/null 2>&1; then yarn install --immutable
        else corepack yarn install --immutable
        fi
        ;;
    bun) bun install --frozen-lockfile ;;
esac

mkdir -p "${sentinel_root}"
node -e '
const fs = require("fs");
const [file, source, image, manager, managerVersion, nodeVersion, abi, platform] = process.argv.slice(1);
fs.writeFileSync(file, JSON.stringify({
  source, image, manager, managerVersion, nodeVersion, nodeAbi: abi, platform
}, null, 2) + "\n");
' "${sentinel}" "${source_fingerprint}" "${image_id}" "${manager}" "${manager_version}" "${node_version}" "${node_abi}" "${platform}"
