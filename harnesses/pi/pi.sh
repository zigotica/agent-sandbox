#!/usr/bin/env bash
# agent-sandbox — Pi harness defaults
# This file is sourced by the main CLI. It defines defaults that can be
# overridden by config.json.

HARNESS_NAME="pi"
HARNESS_IMAGE="agent-sandbox:pi"
HARNESS_DEFAULT_CONFIG_DIR="${HOME}/.pi"
HARNESS_DEFAULT_DATA_DIR="${HOME}/.pi"
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
    ZAI_API_KEY
    OPENCODE_API_KEY
    KIMI_API_KEY
    MINIMAX_API_KEY
    MINIMAX_CN_API_KEY
    OLLAMA_API_BASE
    OLLAMA_API_KEY
    # Pi Configuration
    PI_SKIP_VERSION_CHECK
    PI_CACHE_RETENTION
    PI_PACKAGE_DIR
    # Terminal
    TERM
    COLORTERM
)