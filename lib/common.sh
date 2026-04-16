#!/usr/bin/env bash
# agent-sandbox — Shared functions and harness configuration
# This file is sourced by the main CLI and by harness scripts.
set -euo pipefail

# ─── Constants ────────────────────────────────────────────────────────────────

# Resolve the installation directory, following symlinks.
# Works when the script is invoked via symlink (npm global, Homebrew).
_resolve_lib_path() {
    local src="${BASH_SOURCE[0]}"
    while [[ -L "$src" ]]; do
        local dir
        dir="$(cd "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd "$(dirname "$src")/.." && pwd
}
AGENT_SANDBOX_DIR="$(_resolve_lib_path)"
CONFIG_FILE_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-sandbox"
CONFIG_FILE="${CONFIG_FILE_DIR}/config.json"

# ─── Utility functions ────────────────────────────────────────────────────────

die() {
    echo "error: $*" >&2
    exit 1
}

info() {
    echo "$@"
}

# ─── Config file ──────────────────────────────────────────────────────────────

get_config_file_dir() {
    echo "${CONFIG_FILE_DIR}"
}

get_config_file() {
    echo "${CONFIG_FILE}"
}

# ─── Docker ───────────────────────────────────────────────────────────────────

check_docker() {
    if ! command -v docker > /dev/null 2>&1; then
        die "docker not found — install Docker: https://docs.docker.com/get-docker/"
    fi

    if ! docker info > /dev/null 2>&1; then
        die "docker daemon not running — start Docker Desktop or dockerd"
    fi
}

# ─── Project directory ─────────────────────────────────────────────────────────

get_project_dir() {
    echo "$(pwd)"
}

# ─── Harness loading ──────────────────────────────────────────────────────────

# Load a harness script and export its variables.
# For built-in harnesses, looks in harnesses/<name>/<name>.sh.
# For registered harnesses, looks up the script path from config.json.
load_harness() {
    local harness_name="$1"
    local harness_script=""

    # Check if it's a built-in harness
    local builtin_script="${AGENT_SANDBOX_DIR}/harnesses/${harness_name}/${harness_name}.sh"
    if [[ -f "${builtin_script}" ]]; then
        harness_script="${builtin_script}"
    else
        # Look up in config.json
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            die "Config file not found. Run 'agent-sandbox init' first."
        fi

        local script_from_config
        script_from_config="$(jq -r ".harnesses.\"${harness_name}\".script // \"\"" "${CONFIG_FILE}")"

        if [[ -z "${script_from_config}" ]]; then
            die "Unknown harness '${harness_name}'. Run 'agent-sandbox list' to see available harnesses."
        fi

        harness_script="${script_from_config}"

        if [[ ! -f "${harness_script}" ]]; then
            die "Harness script not found: ${harness_script}"
        fi
    fi

    # Source the harness script to get its defaults
    # shellcheck source=/dev/null
    source "${harness_script}"

    # Override settings from config.json if present
    if [[ -f "${CONFIG_FILE}" ]]; then
        local image_override
        image_override="$(jq -r ".harnesses.\"${harness_name}\".image // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || image_override=""
        if [[ -n "${image_override}" ]]; then
            HARNESS_IMAGE="${image_override}"
        fi

        local mount_override
        mount_override="$(jq -r ".harnesses.\"${harness_name}\".mount_point // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || mount_override=""
        if [[ -n "${mount_override}" ]]; then
            HARNESS_CONFIG_MOUNT_POINT="${mount_override}"
        fi
    fi
}

# ─── Config directory resolution ──────────────────────────────────────────────

# Resolve the config directory for a harness.
# Priority: env var > config.json > harness script default
# All paths are stored and returned as absolute paths using $HOME.
get_config_dir() {
    local harness_name="$1"

    # 1. Env var override (highest priority)
    if [[ -n "${AGENT_SANDBOX_CONFIG_DIR:-}" ]]; then
        echo "${AGENT_SANDBOX_CONFIG_DIR}"
        return
    fi

    # 2. config.json
    if [[ -f "${CONFIG_FILE}" ]]; then
        local config_dir_from_config
        config_dir_from_config="$(jq -r ".harnesses.\"${harness_name}\".config_dir // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || config_dir_from_config=""
        if [[ -n "${config_dir_from_config}" ]]; then
            echo "${config_dir_from_config}"
            return
        fi
    fi

    # 3. Harness script default (HARNESS_DEFAULT_CONFIG_DIR must be set by load_harness)
    if [[ -n "${HARNESS_DEFAULT_CONFIG_DIR:-}" ]]; then
        echo "${HARNESS_DEFAULT_CONFIG_DIR}"
        return
    fi

    die "No config directory found for harness '${harness_name}'. Set it in config.json or export AGENT_SANDBOX_CONFIG_DIR."
}

# Resolve the data directory for a harness.
# Priority: env var > config.json > harness script default
get_data_dir() {
    local harness_name="$1"

    # 1. Env var override (highest priority)
    if [[ -n "${AGENT_SANDBOX_DATA_DIR:-}" ]]; then
        echo "${AGENT_SANDBOX_DATA_DIR}"
        return
    fi

    # 2. config.json
    if [[ -f "${CONFIG_FILE}" ]]; then
        local data_dir_from_config
        data_dir_from_config="$(jq -r ".harnesses.\"${harness_name}\".data_dir // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || data_dir_from_config=""
        if [[ -n "${data_dir_from_config}" ]]; then
            echo "${data_dir_from_config}"
            return
        fi
    fi

    # 3. Harness script default (HARNESS_DEFAULT_DATA_DIR must be set by load_harness)
    if [[ -n "${HARNESS_DEFAULT_DATA_DIR:-}" ]]; then
        echo "${HARNESS_DEFAULT_DATA_DIR}"
        return
    fi

    die "No data directory found for harness '${harness_name}'. Set it in config.json or export AGENT_SANDBOX_DATA_DIR."
}

# ─── Generic harness setting resolution ────────────────────────────────────────

# Resolve any harness setting.
# Priority: config.json > harness script default (already sourced)
get_harness_setting() {
    local harness_name="$1"
    local setting_name="$2"
    local default_value="${3:-}"

    # 1. config.json
    if [[ -f "${CONFIG_FILE}" ]]; then
        local value_from_config
        value_from_config="$(jq -r ".harnesses.\"${harness_name}\".${setting_name} // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || value_from_config=""
        if [[ -n "${value_from_config}" ]]; then
            echo "${value_from_config}"
            return
        fi
    fi

    # 2. Default
    echo "${default_value}"
}

# ─── Image building ──────────────────────────────────────────────────────────

# Check if the Docker image exists; if not, build it.
auto_build_image() {
    if ! docker image inspect "${HARNESS_IMAGE}" > /dev/null 2>&1; then
        info "Docker image '${HARNESS_IMAGE}' not found. Building..."
        build_image
    fi
}

# Build the Docker image for the current harness.
# HARNESS_DOCKERFILE can be set by harness scripts to point to a custom Dockerfile.
# If not set, falls back to harnesses/<name>/Dockerfile.
# If the first argument is "--no-cache", the build will bypass Docker cache.
build_image() {
    local harness_name="${HARNESS_NAME,,}"

    # Determine Dockerfile path
    local dockerfile="${HARNESS_DOCKERFILE:-${AGENT_SANDBOX_DIR}/harnesses/${harness_name}/Dockerfile}"

    if [[ ! -f "${dockerfile}" ]]; then
        die "Dockerfile not found for harness '${HARNESS_NAME}': ${dockerfile}"
    fi

    # Build context is the directory containing the Dockerfile.
    local build_context
    build_context="$(cd "$(dirname "${dockerfile}")" && pwd)"

    # Check for version pin in config.json
    local build_args=()
    if [[ -f "${CONFIG_FILE}" ]]; then
        local pinned_version
        pinned_version="$(jq -r ".harnesses.\"${harness_name}\".version // \"\"" "${CONFIG_FILE}" 2>/dev/null)" || pinned_version=""
        if [[ -n "${pinned_version}" ]]; then
            build_args+=("--build-arg" "VERSION=${pinned_version}")
        fi
    fi

    # Linux needs --network=host for DNS during build
    local build_flags=()
    if [[ "$(uname -s)" == "Linux" ]]; then
        build_flags+=("--network=host")
    fi
    # Add --no-cache if first argument is "--no-cache"
    if [[ "${1:-}" == "--no-cache" ]]; then
        build_flags+=("--no-cache")
    fi

    docker build "${build_flags[@]}" "${build_args[@]}" \
        -f "${dockerfile}" \
        -t "${HARNESS_IMAGE}" \
        "${build_context}"
}

# ─── Container execution ─────────────────────────────────────────────────────

# Run the container for the loaded harness.
# Assumes load_harness() has been called and HARNESS_* variables are set.
# Arguments are passed through to the harness command inside the container.
run_container() {
    check_docker

    # HARNESS_NAME is set by load_harness() which is called before this.
    # Use it to resolve the config and data directories.
    local harness_name="${HARNESS_NAME,,}"

    local config_dir
    config_dir="$(get_config_dir "${harness_name}")"

    local data_dir
    data_dir="$(get_data_dir "${harness_name}")"

    # Ensure directories exist
    mkdir -p "${config_dir}"
    mkdir -p "${data_dir}"

    # Auto-build the image if needed
    auto_build_image

    local project_dir
    project_dir="$(get_project_dir)"

    # Build Docker flags
    local docker_flags=(
        "--rm"
        "--user" "$(id -u):$(id -g)"
        "--privileged"
        "--ipc=none"
        "--net=host"
        "--volume" "${config_dir}:${HARNESS_CONFIG_MOUNT_POINT}"
        "--volume" "${data_dir}:${HARNESS_DATA_MOUNT_POINT}"
        "--volume" "${project_dir}:${project_dir}"
        "--workdir" "${project_dir}"
        "--env" "AGENT_CONFIG_DIR=${HARNESS_CONFIG_MOUNT_POINT}"
        "--env" "AGENT_DATA_DIR=${HARNESS_DATA_MOUNT_POINT}"
        "--env" "TERM=${TERM:-xterm-256color}"
        "--env" "COLORTERM=${COLORTERM:-truecolor}"
    )

    # Pass through harness-specific env vars
    if [[ ${#HARNESS_ENV_VARS[@]} -gt 0 ]]; then
        local var
        for var in "${HARNESS_ENV_VARS[@]}"; do
            if [[ -n "${!var:-}" ]]; then
                docker_flags+=("--env" "${var}=${!var}")
            fi
        done
    fi

    # Extra volumes and flags (set by cmd_test or other callers before invoking run_container)
    if declare -p EXTRA_DOCKER_VOLUMES &>/dev/null && [[ ${#EXTRA_DOCKER_VOLUMES[@]} -gt 0 ]]; then
        docker_flags+=("${EXTRA_DOCKER_VOLUMES[@]}")
    fi

    # Entrypoint override (set by cmd_test or other callers)
    if [[ -n "${ENTRYPOINT_OVERRIDE:-}" ]]; then
        docker_flags+=("--entrypoint" "${ENTRYPOINT_OVERRIDE}")
    fi

    # Harness-specific Docker flags (via get_docker_flags function if defined)
    if declare -f get_docker_flags > /dev/null 2>&1; then
        local extra_flags
        extra_flags="$(get_docker_flags)"
        if [[ -n "${extra_flags}" ]]; then
            read -ra extra_flags_array <<< "${extra_flags}"
            docker_flags+=("${extra_flags_array[@]}")
        fi
    fi

    # Interactive / TTY
    docker_flags+=("--interactive")
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        docker_flags+=("--tty")
    fi

    # Tmux passthrough
    if [[ -n "${TMUX:-}" ]]; then
        tmux set-option -p allow-passthrough on 2>/dev/null || true
        trap 'tmux set-option -p allow-passthrough off 2>/dev/null || true' EXIT
    fi

    # Run the container
    docker run "${docker_flags[@]}" "${HARNESS_IMAGE}" "$@"
}
