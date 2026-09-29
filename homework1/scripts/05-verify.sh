#!/usr/bin/env bash
# Шаг 5. Проверка целостности кластера:
#   сервисы на узлах, 3 живые DataNode и 0 мёртвых, safe mode OFF,
#   Secondary NameNode отвечает, запись/чтение файла с репликацией 3, логи без FATAL/ERROR.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0
expect() {  # expect <название> <получено> <ожидается>
    if [[ "$2" == "$3" ]]; then ok "$1 = $2"; else echo "${C_R}FAIL${C_0} $1 = ${2:-нет данных} (ожидалось $3)"; fail=1; fi
}

log "Шаг 5/5: проверка кластера"
build_node_script
for h in $(all_hosts); do push_node "$h"; done

echo; log "1. Сервисы на узлах"
for h in $(all_hosts); do node_do "$h" status || fail=1; done

echo; log "2. Состояние по данным NameNode (JMX)"
expected="$(count_words $DATANODE_HOSTS)"
expect "Live DataNodes"            "$(nn_metric FSNamesystemState NumLiveDataNodes || true)"           "$expected"
expect "Dead DataNodes"            "$(nn_metric FSNamesystemState NumDeadDataNodes || true)"           0
expect "Stale DataNodes"           "$(nn_metric FSNamesystemState NumStaleDataNodes || true)"          0
expect "Decommissioning DataNodes" "$(nn_metric FSNamesystemState NumDecommissioningDataNodes || true)" 0
expect "Missing blocks"            "$(nn_metric FSNamesystem MissingBlocks || true)"                   0
expect "Corrupt blocks"            "$(nn_metric FSNamesystem CorruptBlocks || true)"                   0
expect "Under-replicated blocks"   "$(nn_metric FSNamesystem UnderReplicatedBlocks || true)"           0

safemode="$(hdfs_admin dfsadmin -safemode get 2>/dev/null || true)"
expect "Safe mode" "$(grep -oE 'ON|OFF' <<< "$safemode" | head -n1 || true)" OFF

snn_url="http://$SECONDARY_NAMENODE_HOST:$SNN_HTTP_PORT/jmx?qry=Hadoop:service=SecondaryNameNode,name=SecondaryNameNodeInfo"
snn_jmx="$(curl -fsS --max-time 10 "$snn_url" 2>/dev/null || true)"
if grep -q HostAndPort <<< "$snn_jmx"; then ok "Secondary NameNode отвечает"; else echo "${C_R}FAIL${C_0} Secondary NameNode не отвечает"; fail=1; fi

echo; log "3. dfsadmin -report"
hdfs_admin dfsadmin -report 2>/dev/null | grep -E '^(Configured Capacity|DFS Remaining|Live datanodes|Dead datanodes|Name:|Hostname:|Decommission Status)' || true

echo; log "4. Запись и чтение тестового файла (replication=$DFS_REPLICATION)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
head -c 16M /dev/urandom > "$tmp"
smoke=/tmp/hdfs-deploy-smoke
hdfs_admin dfs -mkdir -p "$smoke"
hdfs_admin dfs -D dfs.replication="$DFS_REPLICATION" -put -f - "$smoke/file.bin" < "$tmp"
fsck="$(hdfs_admin fsck "$smoke/file.bin" -files -blocks -locations 2>&1 || true)"
sum_local="$(md5sum < "$tmp" | awk '{print $1}')"
sum_hdfs="$(hdfs_admin dfs -cat "$smoke/file.bin" | md5sum | awk '{print $1}')"
hdfs_admin dfs -rm -r -f -skipTrash "$smoke" >/dev/null
expect "fsck файла"              "$(grep -oE 'is (HEALTHY|CORRUPT)' <<< "$fsck" | head -n1 || true)" "is HEALTHY"
expect "реплик блока"            "$(grep -oE 'Live_repl=[0-9]+' <<< "$fsck" | head -n1 | cut -d= -f2 || true)" "$DFS_REPLICATION"
expect "md5 прочитанного файла"  "$sum_hdfs" "$sum_local"
expect "fsck /"                  "$(hdfs_admin fsck / 2>/dev/null | grep -oE 'is (HEALTHY|CORRUPT)' | head -n1 || true)" "is HEALTHY"

echo; log "5. Логи на узлах (ERROR/FATAL)"
for h in $(all_hosts); do
    rc=0
    node_do "$h" logs || rc=$?
    case $rc in
        0) ;;
        3) warn "$h: в логах есть ERROR — посмотрите вывод выше" ; fail=1 ;;
        2) echo "${C_R}FAIL${C_0} $h: в логах есть FATAL"; fail=1 ;;
        *) echo "${C_R}FAIL${C_0} $h: не удалось проверить логи (код $rc)"; fail=1 ;;
    esac
done

echo
if (( fail )); then
    die "проверка не пройдена — см. строки FAIL/WARN выше"
fi
ok "Кластер целостный: NameNode, Secondary NameNode и $expected DataNode работают, деградировавших узлов нет"
cat <<EOM

Web UI NameNode (с вашего компьютера):
    ssh -L $NN_HTTP_PORT:$NAMENODE_HOST:$NN_HTTP_PORT -L $SNN_HTTP_PORT:$SECONDARY_NAMENODE_HOST:$SNN_HTTP_PORT $SSH_USER@$EDGE_PUBLIC_HOST
    NameNode:           http://localhost:$NN_HTTP_PORT/dfshealth.html#tab-datanode
    Secondary NameNode: http://localhost:$SNN_HTTP_PORT/status.html
EOM
