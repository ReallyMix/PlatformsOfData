#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

for step in 00-check 01-download 02-install 03-configure 04-start 05-verify; do
    echo
    bash "scripts/$step.sh"
done
