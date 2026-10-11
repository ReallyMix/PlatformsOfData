#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

for step in 00-check 01-configure 02-start 03-publish 04-verify; do
    echo
    bash "scripts/$step.sh"
done
