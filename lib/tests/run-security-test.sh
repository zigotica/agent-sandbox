#!/bin/sh
# Wrapper that shows a message before running the security test suite.
# This runs inside the container, outside of pi/opencode, so output is immediate.
echo "Running security tests inside Docker container..."
echo ""
exec bash /usr/local/bin/container-security.sh
