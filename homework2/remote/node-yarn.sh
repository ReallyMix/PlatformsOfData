set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_ALL="resourcemanager nodemanager historyserver"
NODE="?"

log()  { echo "  [$NODE] $*"; }
warn() { echo "  [$NODE] ВНИМАНИЕ: $*" >&2; }
die()  { echo "  [$NODE] ОШИБКА: $*" >&2; exit 1; }

has_role() {
    case "$1" in
        resourcemanager) [[ "$NODE" == "$RESOURCEMANAGER_HOST" ]] ;;
        nodemanager)     [[ " $NODEMANAGER_HOSTS " == *" $NODE "* ]] ;;
        historyserver)   [[ "$NODE" == "$HISTORYSERVER_HOST" ]] ;;
        *)               return 1 ;;
    esac
}

my_roles() {
    local r out=""
    for r in $ROLES_ALL; do
        if has_role "$r"; then out+="$r "; fi
    done
    echo "${out:-client}"
}

unit() {
    if [[ "$1" == historyserver ]]; then echo "hadoop-mapred@$1.service"; else echo "hadoop-yarn@$1.service"; fi
}

java_class() {
    case "$1" in
        resourcemanager) echo ResourceManager ;;
        nodemanager)     echo NodeManager ;;
        historyserver)   echo JobHistoryServer ;;
    esac
}


do_configure() {
    local conf="$HADOOP_HOME/etc/hadoop" r
    [[ -x "$HADOOP_HOME/bin/yarn" ]] || die "Hadoop не установлен (сначала разверните homework1)"

    install -m 644 "$STAGE_DIR/conf/yarn-site.xml"   "$conf/yarn-site.xml"
    install -m 644 "$STAGE_DIR/conf/mapred-site.xml" "$conf/mapred-site.xml"

    install -m 644 "$STAGE_DIR/conf/hadoop-yarn@.service"   /etc/systemd/system/hadoop-yarn@.service
    install -m 644 "$STAGE_DIR/conf/hadoop-mapred@.service" /etc/systemd/system/hadoop-mapred@.service
    systemctl daemon-reload

    install -d -m 755 -o "$HADOOP_USER" -g "$HADOOP_USER" "$DATA_DIR/yarn" "$DATA_DIR/yarn/local" "$LOG_DIR/userlogs"

    for r in $ROLES_ALL; do
        if has_role "$r"; then
            systemctl enable --quiet "$(unit "$r")"
        else
            systemctl disable --now --quiet "$(unit "$r")" 2>/dev/null || true
        fi
    done
    log "конфигурация YARN применена, роли узла: $(my_roles)"
}


show_failure() {
    local r=$1
    journalctl -u "$(unit "$r")" -n 20 --no-pager 2>/dev/null || true
    tail -n 40 "$LOG_DIR/hadoop-$HADOOP_USER-$r-"*.log 2>/dev/null || true
}

do_start() {
    local r
    for r in "$@"; do
        has_role "$r" || die "роль $r не назначена этому узлу"
        log "запуск $r"
        if ! systemctl start "$(unit "$r")"; then show_failure "$r"; die "$r не запустился"; fi
        sleep 5
        if ! systemctl is-active --quiet "$(unit "$r")"; then show_failure "$r"; die "$r упал после старта"; fi
        log "$r работает (pid $(systemctl show -p MainPID --value "$(unit "$r")"))"
    done
}

do_stop() {
    local r
    for r in "$@"; do
        log "остановка $r"
        systemctl stop "$(unit "$r")" || true
    done
}


do_status() {
    local r rc=0 roles jps_out
    roles="$(my_roles)"
    if [[ "$roles" == client ]]; then
        log "роль: клиент YARN (конфиги на месте: $(ls "$HADOOP_HOME/etc/hadoop/yarn-site.xml" "$HADOOP_HOME/etc/hadoop/mapred-site.xml" 2>/dev/null | wc -l) из 2)"
        return 0
    fi
    jps_out="$(sudo -u "$HADOOP_USER" "$JAVA_HOME/bin/jps" 2>/dev/null || true)"
    for r in $roles; do
        if systemctl is-active --quiet "$(unit "$r")"; then
            log "$r: active"
        else
            log "$r: НЕ ЗАПУЩЕН"
            rc=1
        fi
        if ! grep -qE "[[:space:]]$(java_class "$r")$" <<< "$jps_out"; then
            log "$r: процесс $(java_class "$r") не найден в jps"
            rc=1
        fi
    done
    log "jps: $(awk '$2 != "Jps" {printf "%s ", $2}' <<< "$jps_out")"
    return $rc
}

do_logs() {
    shopt -s nullglob
    local r roles active cutoff file matches="" found files=() n_err n_fatal
    roles="$(my_roles)"
    if [[ "$roles" == client ]]; then return 0; fi
    for r in $roles; do
        active="$(systemctl show -p ActiveEnterTimestamp --value "$(unit "$r")" 2>/dev/null || true)"
        cutoff="$(date -d "$active" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
        for file in "$LOG_DIR"/hadoop-"$HADOOP_USER"-"$r"-*.log; do
            files+=("$file")
            found="$(awk -v cutoff="$cutoff" '
                (cutoff == "" || substr($0, 1, 19) >= cutoff) &&
                / (ERROR|FATAL) / &&
                $0 !~ /RECEIVED SIGNAL [0-9]+: SIG(TERM|HUP|INT)/ {
                    print FILENAME ":" $0
                }' "$file")"
            if [[ -n "$found" ]]; then matches+="${matches:+$'\n'}$found"; fi
        done
    done
    n_fatal="$(grep -c ' FATAL ' <<< "$matches" || true)"
    n_err="$(grep -c ' ERROR ' <<< "$matches" || true)"
    log "логи YARN: FATAL=$n_fatal ERROR=$n_err (${#files[@]} файлов в $LOG_DIR)"
    if [[ -n "$matches" ]]; then
        tail -n 10 <<< "$matches" | sed "s|^$LOG_DIR/|      |"
    fi
    if (( n_fatal > 0 )); then return 2; fi
    if (( n_err > 0 )); then return 3; fi
    return 0
}

do_purge() {
    local r
    for r in historyserver nodemanager resourcemanager; do
        systemctl disable --now --quiet "$(unit "$r")" 2>/dev/null || true
    done
    rm -f /etc/systemd/system/hadoop-yarn@.service /etc/systemd/system/hadoop-mapred@.service
    systemctl daemon-reload

    rm -f "$HADOOP_HOME/etc/hadoop/yarn-site.xml" "$HADOOP_HOME/etc/hadoop/mapred-site.xml"
    [[ -n "$DATA_DIR" && "$DATA_DIR" != / ]] || die "подозрительный путь DATA_DIR"
    rm -rf "$DATA_DIR/yarn" "$LOG_DIR/userlogs"
    for r in resourcemanager nodemanager historyserver; do
        rm -f "$LOG_DIR/hadoop-$HADOOP_USER-$r-"*
    done
    log "YARN удалён с узла (HDFS не тронут)"
}


main() {
    cd /
    [[ $EUID -eq 0 ]] || { echo "node-yarn.sh нужно запускать от root" >&2; exit 1; }
    local action=${1:-}
    NODE=${2:-}
    if [[ -z "$action" || -z "$NODE" ]]; then
        echo "usage: node-yarn.sh <configure|start|stop|status|logs|purge> <node> [roles...]" >&2
        exit 2
    fi
    shift 2
    export JAVA_HOME HADOOP_HOME

    case "$action" in
        configure) do_configure ;;
        start)     do_start "$@" ;;
        stop)      do_stop "$@" ;;
        status)    do_status ;;
        logs)      do_logs ;;
        purge)     do_purge ;;
        *)         echo "неизвестное действие: $action" >&2; exit 2 ;;
    esac
}

main "$@"
