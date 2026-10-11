#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 2/4: запуск YARN и JobHistory Server"
build_yarn_node_script
for h in $(all_hosts); do push_yarn "$h"; done

log "каталоги в HDFS: /tmp (staging задач, логи, история) и /user/$HADOOP_USER"
hdfs_admin dfs -mkdir -p /tmp "/user/$HADOOP_USER"
hdfs_admin dfs -chmod 1777 /tmp

yarn_do "$RESOURCEMANAGER_HOST" start resourcemanager
wait_port "$RESOURCEMANAGER_HOST" "$RM_RPC_PORT" 90  || die "ResourceManager не открыл порт $RM_RPC_PORT"
wait_port "$RESOURCEMANAGER_HOST" "$RM_HTTP_PORT" 60 || die "ResourceManager не открыл порт $RM_HTTP_PORT"
ok "ResourceManager слушает $RESOURCEMANAGER_HOST:$RM_RPC_PORT и :$RM_HTTP_PORT (Web UI)"

for h in $NODEMANAGER_HOSTS; do yarn_do "$h" start nodemanager; done

expected="$(count_words $NODEMANAGER_HOSTS)"
log "ожидание регистрации NodeManager: $expected шт."
active=0
for _ in $(seq 1 45); do
    active="$(rm_metric NumActiveNMs || echo 0)"
    if (( active >= expected )); then break; fi
    sleep 2
done
(( active >= expected )) || die "зарегистрировано $active из $expected NodeManager — смотрите логи в $LOG_DIR на узлах"
ok "активных NodeManager: $active"

yarn_do "$HISTORYSERVER_HOST" start historyserver
wait_port "$HISTORYSERVER_HOST" "$JHS_HTTP_PORT" 90 || die "JobHistory Server не открыл порт $JHS_HTTP_PORT"
ok "YARN запущен"
