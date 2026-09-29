#!/usr/bin/env bash
# Шаг 4. Форматирование NameNode (только первый раз) и запуск сервисов по порядку:
#        NameNode -> DataNode x3 -> Secondary NameNode.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 4/5: форматирование и запуск HDFS"
build_node_script
for h in $(all_hosts); do push_node "$h"; done

node_do "$NAMENODE_HOST" format

node_do "$NAMENODE_HOST" start namenode
wait_port "$NAMENODE_HOST" "$NN_RPC_PORT" 90  || die "NameNode не открыла порт $NN_RPC_PORT"
wait_port "$NAMENODE_HOST" "$NN_HTTP_PORT" 60 || die "NameNode не открыла порт $NN_HTTP_PORT"
ok "NameNode слушает $NAMENODE_HOST:$NN_RPC_PORT (RPC) и :$NN_HTTP_PORT (Web UI)"

for h in $DATANODE_HOSTS; do node_do "$h" start datanode; done

expected="$(count_words $DATANODE_HOSTS)"
log "ожидание регистрации DataNode: $expected шт."
live=0
for _ in $(seq 1 45); do
    live="$(nn_metric FSNamesystemState NumLiveDataNodes || echo 0)"
    if (( live >= expected )); then break; fi
    sleep 2
done
(( live >= expected )) || die "зарегистрировано $live из $expected DataNode — смотрите логи в $LOG_DIR на DataNode"
ok "живых DataNode: $live"

node_do "$SECONDARY_NAMENODE_HOST" start secondarynamenode
wait_port "$SECONDARY_NAMENODE_HOST" "$SNN_HTTP_PORT" 60 || die "Secondary NameNode не открыла порт $SNN_HTTP_PORT"

log "ожидание выхода NameNode из safe mode"
( cd / && timeout 180 sudo -u "$HADOOP_USER" "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode wait ) \
    || die "NameNode не вышла из safe mode"
ok "HDFS запущен"
