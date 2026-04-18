#!/usr/bin/env bash
# agent-sandbox — Template for scaffolded harness scripts
# Used by `agent-sandbox register <name>`.
# Override defaults below and optionally define get_docker_flags().
#
# Template uses *.template.* names so it does not get picked up as real harness.

HARNESS_NAME=""                        # Display name (e.g. "cursor")
HARNESS_IMAGE=""                       # Docker image tag (e.g. "agent-sandbox:cursor")
HARNESS_DEFAULT_CONFIG_DIR="${HOME}/.config/example"
HARNESS_DEFAULT_DATA_DIR="${HOME}/.local/share/example"
HARNESS_CONFIG_MOUNT_POINT="/agent-config"
HARNESS_DATA_MOUNT_POINT="/agent-data"
HARNESS_DOCKERFILE=""

HARNESS_ENV_VARS=()

# Optional: return extra Docker flags as a space-separated string.
# get_docker_flags() {
#     echo ""
# }