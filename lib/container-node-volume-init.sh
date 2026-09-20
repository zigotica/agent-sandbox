#!/bin/sh
set -eu

uid="$1"
gid="$2"
shift 2

for dependency_root in "$@"; do
    if [ ! -d "${dependency_root}" ]; then
        echo "error: dependency volume target does not exist: ${dependency_root}" >&2
        exit 1
    fi
    chown "${uid}:${gid}" "${dependency_root}"
    chmod u+rwx "${dependency_root}"
done
