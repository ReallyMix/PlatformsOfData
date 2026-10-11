#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 0/4: проверка готовности кластера"

if [[ "$(hostname -s)" != "$EDGE_HOST" ]]; then
    warn "скрипты рассчитаны на запуск с $EDGE_HOST, текущий узел: $(hostname -s)"
fi
for cmd in ssh scp curl openssl sudo; do
    command -v "$cmd" >/dev/null || die "на edge нет утилиты $cmd"
done
sudo -n true 2>/dev/null || die "на edge sudo требует пароль (нужен для установки nginx)"

live="$(nn_metric FSNamesystemState NumLiveDataNodes || true)"
[[ -n "$live" ]] || die "NameNode не отвечает на $NAMENODE_HOST:$NN_HTTP_PORT — сначала разверните HDFS (homework1/deploy.sh)"
expected="$(count_words $DATANODE_HOSTS)"
(( live == expected )) || die "живых DataNode $live из $expected — сначала почините HDFS"
ok "HDFS работает: живых DataNode $live"

printf '%-12s %-24s %-8s %s\n' HOST "РОЛИ YARN" RAM_MB "ПОД КОНТЕЙНЕРЫ"
for h in $(all_hosts); do
    on "$h" "test -x $HADOOP_HOME/bin/yarn && test -x $HADOOP_HOME/bin/mapred" \
        || die "$h: Hadoop не установлен в $HADOOP_HOME"
    roles=""
    [[ "$h" == "$RESOURCEMANAGER_HOST" ]] && roles+="RM "
    [[ " $NODEMANAGER_HOSTS " == *" $h "* ]] && roles+="NM "
    [[ "$h" == "$HISTORYSERVER_HOST" ]] && roles+="JHS "
    ram="$(on "$h" "free -m | awk '/^Mem:/{print \$2}'")"
    nm="-"
    if [[ " $NODEMANAGER_HOSTS " == *" $h "* ]]; then
        nm="${NM_MEMORY_MB} МБ"
        if (( NM_MEMORY_MB * 100 > ram * 60 )); then
            warn "$h: NodeManager отдаёт под контейнеры $NM_MEMORY_MB МБ из $ram МБ — уменьшите NM_MEMORY_MB в config.env"
        fi
    fi
    printf '%-12s %-24s %-8s %s\n' "$h" "${roles:-клиент}" "$ram" "$nm"
done

(( AM_MEMORY_MB <= NM_MEMORY_MB )) || die "AM_MEMORY_MB ($AM_MEMORY_MB) больше NM_MEMORY_MB ($NM_MEMORY_MB) — задача не поместится"
(( MAP_MEMORY_MB <= NM_MEMORY_MB && REDUCE_MEMORY_MB <= NM_MEMORY_MB )) || die "контейнер map/reduce больше NM_MEMORY_MB"

if command -v nginx >/dev/null; then
    ok "nginx уже установлен"
else
    log "nginx не установлен — его поставит шаг 03-publish.sh через apt"
fi
ok "можно разворачивать YARN"
