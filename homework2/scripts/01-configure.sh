#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 1/4: конфигурация YARN и MapReduce"
log "ResourceManager: $RESOURCEMANAGER_HOST | NodeManager: $NODEMANAGER_HOSTS | JobHistory: $HISTORYSERVER_HOST"

render_yarn_configs
ok "конфиги сгенерированы в $YARN_BUILD_DIR/conf"

build_yarn_node_script
for h in $(all_hosts); do
    push_yarn "$h"
    yarn_do "$h" configure
done
ok "конфигурация YARN разложена на все узлы"
