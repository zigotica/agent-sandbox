#!/usr/bin/env bash
# agent-sandbox — opencode harness defaults
# Installs opencode via npm globally in the container.

HARNESS_NAME="opencode"
HARNESS_IMAGE="agent-sandbox:opencode"
HARNESS_DEFAULT_CONFIG_DIR="${HOME}/.config/opencode"
HARNESS_DEFAULT_DATA_DIR="${HOME}/.local/share/opencode"
HARNESS_CONFIG_MOUNT_POINT="/agent-config"
HARNESS_DATA_MOUNT_POINT="/agent-data"

# Dockerfile is in the same directory as this script.
HARNESS_DOCKERFILE="$(dirname "${BASH_SOURCE[0]}")/Dockerfile"

# Environment variables to pass through if set on the host.
HARNESS_ENV_VARS=(
    # AI Provider Keys
    ANTHROPIC_API_KEY
    OPENAI_API_KEY
    GEMINI_API_KEY
    AZURE_OPENAI_API_KEY
    MISTRAL_API_KEY
    GROQ_API_KEY
    CEREBRAS_API_KEY
    XAI_API_KEY
    OPENROUTER_API_KEY
    AI_GATEWAY_API_KEY
    # Terminal
    TERM
    COLORTERM
)