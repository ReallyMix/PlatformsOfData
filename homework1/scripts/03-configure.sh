#!/usr/bin/env bash
# Шаг 3. Генерация конфигов из templates/ и раскладка их на все узлы + systemd unit.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 3/5: конфигурация"
log "NameNode: $NAMENODE_HOST | Secondary NameNode: $SECONDARY_NAMENODE_HOST | DataNode: $DATANODE_HOSTS"
n_dn="$(count_words $DATANODE_HOSTS)"
if (( n_dn < DFS_REPLICATION )); then die "DataNode ($n_dn) меньше, чем dfs.replication ($DFS_REPLICATION)"; fi

render_configs
ok "конфиги сгенерированы в $BUILD_DIR/conf"

build_node_script
for h in $(all_hosts); do
    push_node "$h"
    node_do "$h" configure
done
ok "конфигурация разложена на все узлы"
