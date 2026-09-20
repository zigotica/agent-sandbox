#!/usr/bin/env bash
# Strict Linux dependency isolation for Node projects.

NODE_PACKAGE_ROOTS=()
NODE_PACKAGE_INSTALL_ROOTS=()
NODE_PACKAGE_VOLUMES=()
NODE_INSTALL_ROOTS=()
NODE_INSTALL_MANAGERS=()
NODE_INSTALL_LOCKFILES=()
NODE_DEPENDENCY_DOCKER_FLAGS=()

node_hash_stream() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        die "Neither sha256sum nor shasum is available"
    fi
}

node_hash_file() {
    local file_path="$1"
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "${file_path}" | awk '{print $1}'
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 "${file_path}" | awk '{print $1}'
    else
        die "Neither sha256sum nor shasum is available"
    fi
}

node_hash_text() {
    printf '%s' "$1" | node_hash_stream
}

node_relative_path() {
    local project_dir="$1"
    local target_dir="$2"
    if [[ "${target_dir}" == "${project_dir}" ]]; then
        printf '.'
    else
        printf '%s' "${target_dir#"${project_dir}"/}"
    fi
}

node_package_needs_dependencies() {
    local package_json="$1"
    local package_dir
    package_dir="$(dirname "${package_json}")"

    [[ -d "${package_dir}/node_modules" ]] && return 0
    jq -e '
        ((.dependencies // {}) | length) > 0 or
        ((.devDependencies // {}) | length) > 0 or
        ((.optionalDependencies // {}) | length) > 0 or
        ((.peerDependencies // {}) | length) > 0 or
        ((.workspaces // []) | length) > 0
    ' "${package_json}" > /dev/null 2>&1
}

node_detect_lock_at() {
    local dir="$1"
    local declared=""
    local package_json="${dir}/package.json"
    DETECTED_NODE_MANAGER=""
    DETECTED_NODE_LOCKFILE=""

    if [[ -f "${package_json}" ]]; then
        declared="$(jq -r '.packageManager // ""' "${package_json}" 2>/dev/null || true)"
        declared="${declared%%@*}"
    fi

    local npm_lock=""
    [[ -f "${dir}/npm-shrinkwrap.json" ]] && npm_lock="${dir}/npm-shrinkwrap.json"
    [[ -z "${npm_lock}" && -f "${dir}/package-lock.json" ]] && npm_lock="${dir}/package-lock.json"

    local managers=()
    local locks=()
    if [[ -n "${npm_lock}" ]]; then managers+=("npm"); locks+=("${npm_lock}"); fi
    if [[ -f "${dir}/pnpm-lock.yaml" ]]; then managers+=("pnpm"); locks+=("${dir}/pnpm-lock.yaml"); fi
    if [[ -f "${dir}/yarn.lock" ]]; then managers+=("yarn"); locks+=("${dir}/yarn.lock"); fi
    if [[ -f "${dir}/bun.lock" ]]; then managers+=("bun"); locks+=("${dir}/bun.lock"); fi
    if [[ -f "${dir}/bun.lockb" ]]; then managers+=("bun"); locks+=("${dir}/bun.lockb"); fi

    [[ ${#managers[@]} -eq 0 ]] && return 1

    local index
    if [[ -n "${declared}" ]]; then
        for ((index = 0; index < ${#managers[@]}; index++)); do
            if [[ "${managers[$index]}" == "${declared}" ]]; then
                DETECTED_NODE_MANAGER="${managers[$index]}"
                DETECTED_NODE_LOCKFILE="${locks[$index]}"
                return 0
            fi
        done
    fi

    if [[ ${#managers[@]} -gt 1 ]]; then
        die "Multiple lockfile types found in $(node_relative_path "${NODE_PROJECT_DIR}" "${dir}"); set package.json#packageManager to choose one"
    fi

    DETECTED_NODE_MANAGER="${managers[0]}"
    DETECTED_NODE_LOCKFILE="${locks[0]}"
    return 0
}

node_find_install_root() {
    local package_dir="$1"
    local current="${package_dir}"

    while [[ "${current}" == "${NODE_PROJECT_DIR}" || "${current}" == "${NODE_PROJECT_DIR}/"* ]]; do
        if node_detect_lock_at "${current}"; then
            FOUND_NODE_INSTALL_ROOT="${current}"
            FOUND_NODE_MANAGER="${DETECTED_NODE_MANAGER}"
            FOUND_NODE_LOCKFILE="${DETECTED_NODE_LOCKFILE}"
            return 0
        fi
        [[ "${current}" == "${NODE_PROJECT_DIR}" ]] && break
        current="$(dirname "${current}")"
    done
    return 1
}

node_add_install_root() {
    local root="$1"
    local manager="$2"
    local lockfile="$3"
    local index
    for ((index = 0; index < ${#NODE_INSTALL_ROOTS[@]}; index++)); do
        [[ "${NODE_INSTALL_ROOTS[$index]}" == "${root}" ]] && return
    done
    NODE_INSTALL_ROOTS+=("${root}")
    NODE_INSTALL_MANAGERS+=("${manager}")
    NODE_INSTALL_LOCKFILES+=("${lockfile}")
}

discover_node_dependencies() {
    local project_dir="$1"
    NODE_PROJECT_DIR="$(cd "${project_dir}" && pwd -P)"
    NODE_PACKAGE_ROOTS=()
    NODE_PACKAGE_INSTALL_ROOTS=()
    NODE_PACKAGE_VOLUMES=()
    NODE_INSTALL_ROOTS=()
    NODE_INSTALL_MANAGERS=()
    NODE_INSTALL_LOCKFILES=()
    NODE_DEPENDENCY_DOCKER_FLAGS=()

    local package_json package_dir relative_path
    while IFS= read -r package_json; do
        [[ -n "${package_json}" ]] || continue
        package_dir="$(dirname "${package_json}")"
        relative_path="$(node_relative_path "${NODE_PROJECT_DIR}" "${package_dir}")"

        if [[ "${package_dir}" == *$'\n'* || "${package_dir}" == *','* ]]; then
            die "Node package path cannot contain a newline or comma: ${relative_path}"
        fi
        if ! node_find_install_root "${package_dir}"; then
            if node_package_needs_dependencies "${package_json}"; then
                die "Node package '${relative_path}' has dependencies but no supported lockfile at or above it"
            fi
            continue
        fi

        NODE_PACKAGE_ROOTS+=("${package_dir}")
        NODE_PACKAGE_INSTALL_ROOTS+=("${FOUND_NODE_INSTALL_ROOT}")
        node_add_install_root "${FOUND_NODE_INSTALL_ROOT}" "${FOUND_NODE_MANAGER}" "${FOUND_NODE_LOCKFILE}"
    done < <(
        find "${NODE_PROJECT_DIR}" \
            -type d \( -name .git -o -name node_modules -o -name dist -o -name build -o -name coverage -o -name .next -o -name .cache \) -prune -o \
            -type f -name package.json -print | LC_ALL=C sort
    )
}

node_source_fingerprint() {
    local install_root="$1"
    local lockfile="$2"
    local manager="$3"
    local index
    {
        printf 'manager\t%s\n' "${manager}"
        printf 'lock\t%s\t%s\n' "$(node_relative_path "${NODE_PROJECT_DIR}" "${lockfile}")" "$(node_hash_file "${lockfile}")"
        local config_file
        for config_file in pnpm-workspace.yaml .npmrc .yarnrc.yml bunfig.toml; do
            if [[ -f "${install_root}/${config_file}" ]]; then
                printf 'config\t%s\t%s\n' \
                    "$(node_relative_path "${NODE_PROJECT_DIR}" "${install_root}/${config_file}")" \
                    "$(node_hash_file "${install_root}/${config_file}")"
            fi
        done
        for ((index = 0; index < ${#NODE_PACKAGE_ROOTS[@]}; index++)); do
            if [[ "${NODE_PACKAGE_INSTALL_ROOTS[$index]}" == "${install_root}" ]]; then
                printf 'package\t%s\t%s\n' \
                    "$(node_relative_path "${NODE_PROJECT_DIR}" "${NODE_PACKAGE_ROOTS[$index]}/package.json")" \
                    "$(node_hash_file "${NODE_PACKAGE_ROOTS[$index]}/package.json")"
            fi
        done
    } | node_hash_stream
}

node_volume_for_package() {
    local project_hash="$1"
    local package_root="$2"
    local package_hash
    package_hash="$(node_hash_text "$(node_relative_path "${NODE_PROJECT_DIR}" "${package_root}")" | cut -c1-16)"
    printf 'agent-sandbox-node-%s-%s' "${project_hash}" "${package_hash}"
}

prepare_node_dependencies() {
    local project_dir="$1"
    local image="$2"
    local config_dir="$3"
    local data_dir="$4"
    local config_mount="$5"
    local data_mount="$6"

    discover_node_dependencies "${project_dir}"
    [[ ${#NODE_PACKAGE_ROOTS[@]} -eq 0 ]] && return

    local project_hash image_id
    project_hash="$(node_hash_text "${NODE_PROJECT_DIR}" | cut -c1-16)"
    image_id="$(docker image inspect "${image}" --format '{{.Id}}')"

    local index package_root relative_path volume_name mount_spec install_root manager root_index
    for ((index = 0; index < ${#NODE_PACKAGE_ROOTS[@]}; index++)); do
        package_root="${NODE_PACKAGE_ROOTS[$index]}"
        install_root="${NODE_PACKAGE_INSTALL_ROOTS[$index]}"
        relative_path="$(node_relative_path "${NODE_PROJECT_DIR}" "${package_root}")"
        volume_name="$(node_volume_for_package "${project_hash}" "${package_root}")"
        manager=""
        for ((root_index = 0; root_index < ${#NODE_INSTALL_ROOTS[@]}; root_index++)); do
            if [[ "${NODE_INSTALL_ROOTS[$root_index]}" == "${install_root}" ]]; then
                manager="${NODE_INSTALL_MANAGERS[$root_index]}"
                break
            fi
        done
        docker volume create \
            --label "agent-sandbox.kind=node-dependencies" \
            --label "agent-sandbox.project=${project_hash}" \
            --label "agent-sandbox.project-path=${NODE_PROJECT_DIR}" \
            --label "agent-sandbox.package=${relative_path}" \
            --label "agent-sandbox.manager=${manager}" \
            "${volume_name}" > /dev/null
        NODE_PACKAGE_VOLUMES+=("${volume_name}")
        mount_spec="type=volume,source=${volume_name},target=${package_root}/node_modules,volume-nocopy"
        NODE_DEPENDENCY_DOCKER_FLAGS+=("--mount" "${mount_spec}")
    done

    local volume_init_script="${AGENT_SANDBOX_DIR}/lib/container-node-volume-init.sh"
    local dependency_roots=()
    for package_root in "${NODE_PACKAGE_ROOTS[@]}"; do
        dependency_roots+=("${package_root}/node_modules")
    done
    if ! docker run --rm \
        --user "0:0" \
        --volume "${NODE_PROJECT_DIR}:${NODE_PROJECT_DIR}" \
        --volume "${volume_init_script}:/usr/local/bin/agent-sandbox-node-volume-init:ro" \
        "${NODE_DEPENDENCY_DOCKER_FLAGS[@]}" \
        --entrypoint /bin/sh \
        "${image}" \
        /usr/local/bin/agent-sandbox-node-volume-init \
        "$(id -u)" "$(id -g)" "${dependency_roots[@]}"; then
        die "Could not initialize Linux dependency volume ownership"
    fi

    info "Preparing Linux dependencies"
    info ""

    local lockfile source_fingerprint lock_before root_relative sentinel_root
    local prep_script="${AGENT_SANDBOX_DIR}/lib/container-node-prepare.sh"
    for ((root_index = 0; root_index < ${#NODE_INSTALL_ROOTS[@]}; root_index++)); do
        install_root="${NODE_INSTALL_ROOTS[$root_index]}"
        manager="${NODE_INSTALL_MANAGERS[$root_index]}"
        lockfile="${NODE_INSTALL_LOCKFILES[$root_index]}"
        root_relative="$(node_relative_path "${NODE_PROJECT_DIR}" "${install_root}")"
        source_fingerprint="$(node_source_fingerprint "${install_root}" "${lockfile}" "${manager}")"
        lock_before="$(node_hash_file "${lockfile}")"
        sentinel_root="${install_root}/node_modules"

        info "  ${root_relative} (${manager})"
        local install_status=0
        docker run --rm \
            --user "$(id -u):$(id -g)" \
            --privileged \
            --ipc=none \
            --net=host \
            --volume "${config_dir}:${config_mount}" \
            --volume "${data_dir}:${data_mount}" \
            --volume "${NODE_PROJECT_DIR}:${NODE_PROJECT_DIR}" \
            --volume "${prep_script}:/usr/local/bin/agent-sandbox-node-prepare:ro" \
            "${NODE_DEPENDENCY_DOCKER_FLAGS[@]}" \
            --workdir "${install_root}" \
            --env "HOME=/home/agentuser" \
            --env "CI=true" \
            --env "AGENT_CONFIG_DIR=${config_mount}" \
            --env "AGENT_DATA_DIR=${data_mount}" \
            --entrypoint /bin/sh \
            "${image}" \
            /usr/local/bin/agent-sandbox-node-prepare \
            "${manager}" "${source_fingerprint}" "${image_id}" "${sentinel_root}" || install_status=$?

        if [[ "$(node_hash_file "${lockfile}")" != "${lock_before}" ]]; then
            die "Strict dependency installation modified '${lockfile}'; refusing to start the agent"
        fi
        if [[ "$(node_source_fingerprint "${install_root}" "${lockfile}" "${manager}")" != "${source_fingerprint}" ]]; then
            die "Strict dependency installation modified package-manager metadata under '${root_relative}'; refusing to start the agent"
        fi
        if [[ ${install_status} -ne 0 ]]; then
            die "Strict Linux dependency installation failed for '${root_relative}' (${manager}); the lockfile may omit Linux-specific dependencies"
        fi
    done
    info "Dependencies ready."
    info ""
}

node_dependency_project_hash() {
    local project_dir
    project_dir="$(cd "$1" && pwd -P)"
    node_hash_text "${project_dir}" | cut -c1-16
}
