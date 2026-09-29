#!/usr/bin/env bash
# Полное развёртывание HDFS-кластера одной командой (запускать на edge-ноде под team).
# Каждый шаг идемпотентен: при ошибке исправьте причину и просто запустите снова.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

for step in 00-check 01-download 02-install 03-configure 04-start 05-verify; do
    echo
    bash "scripts/$step.sh"
done
