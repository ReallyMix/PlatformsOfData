#!/usr/bin/env bash
# Остановка HDFS в обратном порядке: Secondary NameNode -> DataNode -> NameNode.
# Запуск обратно: scripts/04-start.sh (повторного форматирования не будет).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "остановка HDFS"
build_node_script
for h in $(all_hosts); do push_node "$h"; done
node_do "$SECONDARY_NAMENODE_HOST" stop secondarynamenode
for h in $DATANODE_HOSTS; do node_do "$h" stop datanode; done
node_do "$NAMENODE_HOST" stop namenode
ok "HDFS остановлен"
