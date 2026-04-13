#!/usr/bin/env bash
# agent-sandbox — Template for new harness scripts
# Copy this folder to create a new harness. Override the defaults below
# and optionally define get_docker_flags().
#
# Register with:
#   agent-sandbox register <name> /path/to/this/folder/<name>.sh --config-dir $HOME/.config/<name> --data-dir $HOME/.local/share/<name>
#
# The Dockerfile and entrypoint.template.sh in this folder are starting points
# for building the container image. Edit them for your harness.

HARNESS_NAME=""                        # Display name (e.g. "cursor")
HARNESS_IMAGE=""                       # Docker image tag (e.g. "agent-sandbox:cursor")
HARNESS_DEFAULT_CONFIG_DIR="${HOME}/.config/aider"  # Config dir (use $HOME, not ~)
HARNESS_DEFAULT_DATA_DIR="${HOME}/.local/share/aider" # Data dir (sessions, DB, etc.)
HARNESS_CONFIG_MOUNT_POINT="/agent-config"            # Config mount point in container
HARNESS_DATA_MOUNT_POINT="/agent-data"                # Data mount point in container
HARNESS_DOCKERFILE=""                  # Path to Dockerfile (empty = built-in location)

# Environment variables to pass through if set on the host.
HARNESS_ENV_VARS=()

# Optional: return extra Docker flags as a space-separated string.
# get_docker_flags() {
#     echo ""
# }