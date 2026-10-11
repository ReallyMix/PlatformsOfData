#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "остановка YARN"
build_yarn_node_script
for h in $(all_hosts); do push_yarn "$h"; done
yarn_do "$HISTORYSERVER_HOST" stop historyserver
for h in $NODEMANAGER_HOSTS; do yarn_do "$h" stop nodemanager; done
yarn_do "$RESOURCEMANAGER_HOST" stop resourcemanager
ok "YARN остановлен"
