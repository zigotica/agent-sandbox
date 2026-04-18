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

get_harness_config_dir() {
    local harness_name="$1"
    echo "${CONFIG_FILE_DIR}/harnesses/${harness_name}"
}

get_harness_config_value() {
    local harness_name="$1"
    local field_name="$2"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo ""
        return
    fi

    jq -r --arg name "${harness_name}" --arg field "${field_name}" \
        '.harnesses[$name][$field] // ""' "${CONFIG_FILE}" 2>/dev/null || true
}

json_array_from_bash_array() {
    if [[ $# -eq 0 ]]; then
        echo "[]"
        return
    fi

    printf '%s\n' "$@" | jq -R . | jq -s .
}

write_harness_config_entry() {
    local harness_name="$1"
    local harness_dir="$2"
    local config_dir="$3"
    local data_dir="$4"
    local image="$5"
    local run_command="${6:-}"
    local env_vars_json="${7:-[]}"
    local version="${8:-}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        die "Config file not found: ${CONFIG_FILE}. Run 'agent-sandbox init' first."
    fi

    local tmp_file
    tmp_file="$(mktemp)"
    jq --arg name "${harness_name}" \
       --arg harness_dir "${harness_dir}" \
       --arg config_dir "${config_dir}" \
       --arg data_dir "${data_dir}" \
       --arg image "${image}" \
       --arg run_command "${run_command}" \
       --argjson env_vars "${env_vars_json}" \
       --arg version "${version}" \
       '.harnesses[$name] = {
            name: $name,
            harness_dir: $harness_dir,
            config_dir: $config_dir,
            data_dir: $data_dir,
            image: $image,
            run_command: $run_command,
            env_vars: $env_vars,
            version: $version
        }' "${CONFIG_FILE}" > "${tmp_file}" && mv "${tmp_file}" "${CONFIG_FILE}"
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
# Harness metadata lives in config.json, with copied harness files under
# $HOME/.config/agent-sandbox/harnesses/<name>/.
load_harness() {
    local harness_name="$1"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        die "Config file not found. Run 'agent-sandbox init' first."
    fi

    local harness_dir
    harness_dir="$(get_harness_config_value "${harness_name}" "harness_dir")"
    if [[ -z "${harness_dir}" ]]; then
        die "Unknown harness '${harness_name}'. Run 'agent-sandbox list' to see available harnesses."
    fi

    local script_path="${harness_dir}/${harness_name}.sh"
    if [[ ! -f "${script_path}" ]]; then
        die "Harness script not found: ${script_path}"
    fi

    # shellcheck source=/dev/null
    source "${script_path}"

    # Config is source of truth. Keep harness name stable by key.
    HARNESS_NAME="${harness_name}"

    local config_value
    config_value="$(get_harness_config_value "${harness_name}" "image")"
    [[ -n "${config_value}" ]] && HARNESS_IMAGE="${config_value}"

    config_value="$(get_harness_config_value "${harness_name}" "config_dir")"
    [[ -n "${config_value}" ]] && HARNESS_DEFAULT_CONFIG_DIR="${config_value}"

    config_value="$(get_harness_config_value "${harness_name}" "data_dir")"
    [[ -n "${config_value}" ]] && HARNESS_DEFAULT_DATA_DIR="${config_value}"

    HARNESS_ENV_VARS=()
    local env_var
    while IFS= read -r env_var; do
        [[ -n "${env_var}" ]] || continue
        HARNESS_ENV_VARS+=("${env_var}")
    done < <(jq -r --arg name "${harness_name}" '.harnesses[$name].env_vars[]? // empty' "${CONFIG_FILE}" 2>/dev/null)
}

# ─── Config directory resolution ──────────────────────────────────────────────

# Resolve the config directory for a harness.
# Priority: env var > config.json > harness script default
get_config_dir() {
    local harness_name="$1"

    if [[ -n "${AGENT_SANDBOX_CONFIG_DIR:-}" ]]; then
        echo "${AGENT_SANDBOX_CONFIG_DIR}"
        return
    fi

    local config_dir_from_config
    config_dir_from_config="$(get_harness_config_value "${harness_name}" "config_dir")"
    if [[ -n "${config_dir_from_config}" ]]; then
        echo "${config_dir_from_config}"
        return
    fi

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

    if [[ -n "${AGENT_SANDBOX_DATA_DIR:-}" ]]; then
        echo "${AGENT_SANDBOX_DATA_DIR}"
        return
    fi

    local data_dir_from_config
    data_dir_from_config="$(get_harness_config_value "${harness_name}" "data_dir")"
    if [[ -n "${data_dir_from_config}" ]]; then
        echo "${data_dir_from_config}"
        return
    fi

    if [[ -n "${HARNESS_DEFAULT_DATA_DIR:-}" ]]; then
        echo "${HARNESS_DEFAULT_DATA_DIR}"
        return
    fi

    die "No data directory found for harness '${harness_name}'. Set it in config.json or export AGENT_SANDBOX_DATA_DIR."
}

# ─── Harness asset copying ─────────────────────────────────────────────────────

copy_harness_assets() {
    local source_script="$1"
    local harness_name="$2"
    local target_dir="$3"

    local source_dir
    source_dir="$(cd "$(dirname "${source_script}")" && pwd)"

    local source_dockerfile="${source_dir}/Dockerfile"
    local source_entrypoint="${source_dir}/entrypoint.sh"

    if [[ ! -f "${source_script}" ]]; then
        die "Harness script not found: ${source_script}"
    fi
    if [[ ! -f "${source_dockerfile}" ]]; then
        die "Dockerfile not found for harness '${harness_name}': ${source_dockerfile}"
    fi
    if [[ ! -f "${source_entrypoint}" ]]; then
        die "Entrypoint not found for harness '${harness_name}': ${source_entrypoint}"
    fi

    rm -rf "${target_dir}"
    mkdir -p "${target_dir}"
    cp "${source_script}" "${target_dir}/${harness_name}.sh"
    cp "${source_dockerfile}" "${target_dir}/Dockerfile"
    cp "${source_entrypoint}" "${target_dir}/entrypoint.sh"
    chmod +x "${target_dir}/${harness_name}.sh" "${target_dir}/entrypoint.sh"
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

    local dockerfile="${HARNESS_DOCKERFILE:-${AGENT_SANDBOX_DIR}/harnesses/${harness_name}/Dockerfile}"

    if [[ ! -f "${dockerfile}" ]]; then
        die "Dockerfile not found for harness '${HARNESS_NAME}': ${dockerfile}"
    fi

    local build_context
    build_context="$(cd "$(dirname "${dockerfile}")" && pwd)"

    local build_args=()
    if [[ -f "${CONFIG_FILE}" ]]; then
        local pinned_version
        pinned_version="$(jq -r --arg name "${harness_name}" '.harnesses[$name].version // ""' "${CONFIG_FILE}" 2>/dev/null)" || pinned_version=""
        if [[ -n "${pinned_version}" ]]; then
            build_args+=("--build-arg" "VERSION=${pinned_version}")
        fi
    fi

    local build_flags=()
    if [[ "$(uname -s)" == "Linux" ]]; then
        build_flags+=("--network=host")
    fi
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

    local harness_name="${HARNESS_NAME,,}"

    local config_dir
    config_dir="$(get_config_dir "${harness_name}")"

    local data_dir
    data_dir="$(get_data_dir "${harness_name}")"

    mkdir -p "${config_dir}"
    mkdir -p "${data_dir}"

    auto_build_image

    local project_dir
    project_dir="$(get_project_dir)"

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

    if declare -p HARNESS_ENV_VARS > /dev/null 2>&1 && [[ ${#HARNESS_ENV_VARS[@]} -gt 0 ]]; then
        local var
        for var in "${HARNESS_ENV_VARS[@]}"; do
            if [[ -n "${!var:-}" ]]; then
                docker_flags+=("--env" "${var}=${!var}")
            fi
        done
    fi

    if declare -p EXTRA_DOCKER_VOLUMES > /dev/null 2>&1 && [[ ${#EXTRA_DOCKER_VOLUMES[@]} -gt 0 ]]; then
        docker_flags+=("${EXTRA_DOCKER_VOLUMES[@]}")
    fi

    if [[ -n "${ENTRYPOINT_OVERRIDE:-}" ]]; then
        docker_flags+=("--entrypoint" "${ENTRYPOINT_OVERRIDE}")
    fi

    if declare -f get_docker_flags > /dev/null 2>&1; then
        local extra_flags
        extra_flags="$(get_docker_flags)"
        if [[ -n "${extra_flags}" ]]; then
            read -ra extra_flags_array <<< "${extra_flags}"
            docker_flags+=("${extra_flags_array[@]}")
        fi
    fi

    docker_flags+=("--interactive")
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        docker_flags+=("--tty")
    fi

    if [[ -n "${TMUX:-}" ]]; then
        tmux set-option -p allow-passthrough on 2>/dev/null || true
        trap 'tmux set-option -p allow-passthrough off 2>/dev/null || true' EXIT
    fi

    docker run "${docker_flags[@]}" "${HARNESS_IMAGE}" "$@"
}
