# ---------------------------------------------------------------------
#  remote/node.sh — выполняется НА УЗЛЕ от root.
#
#  scripts/lib.sh склеивает config.env + этот файл в build/node.sh,
#  копирует его на узел в /tmp/hdfs-deploy/ и запускает:
#      sudo bash /tmp/hdfs-deploy/node.sh <действие> <имя-узла> [роли...]
#
#  Действия: install | configure | format | start | stop | status | logs | purge
# ---------------------------------------------------------------------
set -euo pipefail

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLES_ALL="namenode secondarynamenode datanode"
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
NODE="?"

log()  { echo "  [$NODE] $*"; }
warn() { echo "  [$NODE] ВНИМАНИЕ: $*" >&2; }
die()  { echo "  [$NODE] ОШИБКА: $*" >&2; exit 1; }

has_role() {
    case "$1" in
        namenode)          [[ "$NODE" == "$NAMENODE_HOST" ]] ;;
        secondarynamenode) [[ "$NODE" == "$SECONDARY_NAMENODE_HOST" ]] ;;
        datanode)          [[ " $DATANODE_HOSTS " == *" $NODE "* ]] ;;
        *)                 return 1 ;;
    esac
}

my_roles() {
    local r out=""
    for r in $ROLES_ALL; do
        if has_role "$r"; then out+="$r "; fi
    done
    echo "${out:-client}"
}

as_hadoop() { sudo -u "$HADOOP_USER" -- "$@"; }

unit() { echo "hadoop-hdfs@$1.service"; }

# ---------------------------------------------------------------- install

# Прописывает все узлы кластера в /etc/hosts и убирает привязку их имён
# к 127.0.x.x (иначе NameNode/DataNode слушают loopback и не видят друг друга).
fix_hosts() {
    local entry names="" ips="" tmp
    for entry in $CLUSTER_HOSTS; do
        names+="${entry%%:*} "
        ips+="${entry##*:} "
    done

    if [[ ! -e "$HOSTS_FILE.pre-hdfs" ]]; then cp -p "$HOSTS_FILE" "$HOSTS_FILE.pre-hdfs"; fi

    tmp="$(mktemp)"
    awk -v names="$names" -v ips="$ips" '
        BEGIN {
            n = split(names, a, " "); for (i = 1; i <= n; i++) name[a[i]] = 1
            n = split(ips,   b, " "); for (i = 1; i <= n; i++) ip[b[i]]   = 1
        }
        /^# BEGIN hdfs-cluster/ { skip = 1; next }
        /^# END hdfs-cluster/   { skip = 0; next }
        skip                    { next }
        NF == 0 || /^[ \t]*#/   { print; next }
        ($1 in ip)              { next }
        {
            line = $1; kept = 0
            for (i = 2; i <= NF; i++) {
                if (substr($i, 1, 1) == "#") { for (; i <= NF; i++) line = line " " $i; break }
                if (!($i in name)) { line = line " " $i; kept++ }
            }
            if (kept > 0) print line
        }' "$HOSTS_FILE" > "$tmp"
    {
        echo "# BEGIN hdfs-cluster (managed by hdfs-cluster-deploy)"
        for entry in $CLUSTER_HOSTS; do printf '%s\t%s\n' "${entry##*:}" "${entry%%:*}"; done
        echo "# END hdfs-cluster"
    } >> "$tmp"
    cat "$tmp" > "$HOSTS_FILE"
    rm -f "$tmp"
    log "/etc/hosts обновлён (резервная копия: $HOSTS_FILE.pre-hdfs)"

    if [[ "$HOSTS_FILE" == /etc/hosts ]]; then
        local h addr
        for h in $names; do
            addr="$(getent hosts "$h" | awk 'NR==1{print $1}')"
            [[ -n "$addr" ]] || die "имя $h не резолвится"
            [[ "$addr" != 127.* ]] || die "имя $h резолвится в loopback ($addr)"
        done
        if [[ "$(hostname -s)" != "$NODE" ]]; then
            warn "hostname узла '$(hostname -s)' не совпадает с '$NODE' (не критично: адреса заданы явно)"
        fi
    fi
}

create_user() {
    if id -u "$HADOOP_USER" >/dev/null 2>&1; then
        log "пользователь $HADOOP_USER уже существует"
    else
        useradd --system --create-home --shell /bin/bash --user-group "$HADOOP_USER"
        log "создан системный пользователь $HADOOP_USER"
    fi
}

# install_tarball <архив в dist/> <каталог установки> <симлинк> <файл-проверка>
install_tarball() {
    local file=$1 dir=$2 link=$3 check=$4
    local tgz="$STAGE_DIR/dist/$file"

    if [[ -x "$dir/$check" ]]; then
        log "$(basename "$dir") уже установлен"
    else
        [[ -f "$tgz" ]] || die "не найден $tgz (сначала scripts/01-download.sh)"
        log "распаковка $file -> $dir"
        rm -rf "$dir.partial"
        mkdir -p "$dir.partial"
        tar -xzf "$tgz" -C "$dir.partial" --strip-components=1 --no-same-owner
        [[ -x "$dir.partial/$check" ]] || die "в архиве $file нет $check"
        rm -rf "$dir"
        mv "$dir.partial" "$dir"
    fi

    if [[ -d "$link" && ! -L "$link" ]]; then
        die "$link — обычный каталог, а должен быть симлинком; переименуйте его и повторите"
    fi
    ln -sfn "$dir" "$link"
}

do_install() {
    fix_hosts
    create_user
    install_tarball "jdk-$JAVA_MAJOR.tar.gz"          "$INSTALL_DIR/jdk-$JAVA_MAJOR"          "$JAVA_HOME"   bin/java
    install_tarball "hadoop-$HADOOP_VERSION.tar.gz"   "$INSTALL_DIR/hadoop-$HADOOP_VERSION"   "$HADOOP_HOME" bin/hdfs

    install -d -m 755 -o "$HADOOP_USER" -g "$HADOOP_USER" "$DATA_DIR" "$PID_DIR" "$LOG_DIR"

    cat > /etc/profile.d/hadoop.sh <<EOF
# hdfs-cluster-deploy
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=\$PATH:$JAVA_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF

    log "Java:   $("$JAVA_HOME/bin/java" -version 2>&1 | sed -n 1p)"
    log "Hadoop: $("$HADOOP_HOME/bin/hadoop" version 2>/dev/null | sed -n 1p)"
}

# -------------------------------------------------------------- configure

do_configure() {
    local conf="$HADOOP_HOME/etc/hadoop" f r
    [[ -x "$HADOOP_HOME/bin/hdfs" ]] || die "Hadoop не установлен (сначала scripts/02-install.sh)"

    for f in core-site.xml hdfs-site.xml workers; do
        install -m 644 "$STAGE_DIR/conf/$f" "$conf/$f"
    done

    # hadoop-env.sh и log4j.properties: оригинал + наш блок (идемпотентно)
    if [[ ! -f "$conf/hadoop-env.sh.orig" ]]; then cp -p "$conf/hadoop-env.sh" "$conf/hadoop-env.sh.orig"; fi
    { cat "$conf/hadoop-env.sh.orig"; echo; cat "$STAGE_DIR/conf/hadoop-env.sh"; } > "$conf/hadoop-env.sh"

    if [[ ! -f "$conf/log4j.properties.orig" ]]; then cp -p "$conf/log4j.properties" "$conf/log4j.properties.orig"; fi
    { cat "$conf/log4j.properties.orig"; echo
      echo "# hdfs-cluster-deploy: убрать шумное предупреждение про native-библиотеки"
      echo "log4j.logger.org.apache.hadoop.util.NativeCodeLoader=ERROR"; } > "$conf/log4j.properties"

    install -m 644 "$STAGE_DIR/conf/hadoop-hdfs@.service" /etc/systemd/system/hadoop-hdfs@.service
    systemctl daemon-reload

    for r in $ROLES_ALL; do
        if has_role "$r"; then
            systemctl enable --quiet "$(unit "$r")"
        else
            systemctl disable --now --quiet "$(unit "$r")" 2>/dev/null || true
        fi
    done
    log "конфигурация применена, роли узла: $(my_roles)"
}

# ----------------------------------------------------------------- format

do_format() {
    has_role namenode || die "этот узел не NameNode"
    local version="$DATA_DIR/nn/current/VERSION"
    if [[ -f "$version" ]]; then
        log "NameNode уже отформатирована ($(grep '^clusterID=' "$version")) — пропускаю"
        return 0
    fi
    log "форматирование NameNode (clusterID=$CLUSTER_ID)"
    if ! as_hadoop "$HADOOP_HOME/bin/hdfs" namenode -format -clusterid "$CLUSTER_ID" -nonInteractive \
            </dev/null >"$LOG_DIR/namenode-format.out" 2>&1; then
        tail -n 30 "$LOG_DIR/namenode-format.out" >&2
        die "форматирование не удалось"
    fi
    [[ -f "$version" ]] || die "после форматирования нет $version"
    log "NameNode отформатирована"
}

# ------------------------------------------------------------ start / stop

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

# ---------------------------------------------------------- status / logs

do_status() {
    local r expected rc=0 roles jps_out
    roles="$(my_roles)"
    if [[ "$roles" == client ]]; then
        log "роль: клиент HDFS ($("$HADOOP_HOME/bin/hdfs" version 2>/dev/null | sed -n 1p))"
        return 0
    fi
    jps_out="$(as_hadoop "$JAVA_HOME/bin/jps" 2>/dev/null || true)"
    for r in $roles; do
        case "$r" in
            namenode) expected=NameNode ;;
            secondarynamenode) expected=SecondaryNameNode ;;
            datanode) expected=DataNode ;;
        esac
        if systemctl is-active --quiet "$(unit "$r")"; then
            log "$r: active"
        else
            log "$r: НЕ ЗАПУЩЕН"
            rc=1
        fi
        if ! grep -qE "[[:space:]]${expected}$" <<< "$jps_out"; then
            log "$r: процесс $expected не найден в jps"
            rc=1
        fi
    done
    log "jps: $(awk '$2 != "Jps" {printf "%s ", $2}' <<< "$jps_out")"
    return $rc
}

# Ищет ERROR/FATAL в текущих логах демонов. Строки "RECEIVED SIGNAL 15: SIGTERM"
# пишутся с уровнем ERROR при штатной остановке — их не считаем.
do_logs() {
    shopt -s nullglob
    local r active cutoff file matches="" role_matches files=() n_err n_fatal
    for r in $(my_roles); do
        active="$(systemctl show -p ActiveEnterTimestamp --value "$(unit "$r")" 2>/dev/null || true)"
        cutoff="$(date -d "$active" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)"
        for file in "$LOG_DIR"/hadoop-"$HADOOP_USER"-"$r"-*.log; do
            files+=("$file")
            role_matches="$(awk -v cutoff="$cutoff" '
                (cutoff == "" || substr($0, 1, 19) >= cutoff) &&
                / (ERROR|FATAL) / &&
                $0 !~ /RECEIVED SIGNAL [0-9]+: SIG(TERM|HUP|INT)/ {
                    print FILENAME ":" $0
                }' "$file")"
            if [[ -n "$role_matches" ]]; then matches+="${matches:+$'\n'}$role_matches"; fi
        done
    done
    if (( ${#files[@]} == 0 )); then
        log "логов демонов нет"
        return 0
    fi
    n_fatal="$(grep -c ' FATAL ' <<< "$matches" || true)"
    n_err="$(grep -c ' ERROR ' <<< "$matches" || true)"
    log "логи: FATAL=$n_fatal ERROR=$n_err (${#files[@]} файлов в $LOG_DIR)"
    if [[ -n "$matches" ]]; then
        tail -n 10 <<< "$matches" | sed "s|^$LOG_DIR/|      |"
    fi
    if (( n_fatal > 0 )); then return 2; fi
    if (( n_err > 0 )); then return 3; fi
    return 0
}

# ------------------------------------------------------------------ purge

do_purge() {
    local r l
    for r in secondarynamenode datanode namenode; do
        systemctl disable --now --quiet "$(unit "$r")" 2>/dev/null || true
    done
    rm -f /etc/systemd/system/hadoop-hdfs@.service
    systemctl daemon-reload

    [[ -n "$DATA_DIR" && "$DATA_DIR" != / && -n "$LOG_DIR" && "$LOG_DIR" != / ]] || die "подозрительные пути DATA_DIR/LOG_DIR"
    rm -rf "$DATA_DIR" "$LOG_DIR" \
           "$INSTALL_DIR/hadoop-$HADOOP_VERSION" "$INSTALL_DIR/jdk-$JAVA_MAJOR" \
           /etc/profile.d/hadoop.sh
    for l in "$HADOOP_HOME" "$JAVA_HOME"; do
        if [[ -L "$l" ]]; then rm -f "$l"; fi
    done
    log "HDFS, Java, данные и логи удалены (пользователь $HADOOP_USER и /etc/hosts оставлены)"
}

# ------------------------------------------------------------------- main

main() {
    cd /
    [[ $EUID -eq 0 ]] || { echo "node.sh нужно запускать от root" >&2; exit 1; }
    local action=${1:-}
    NODE=${2:-}
    if [[ -z "$action" || -z "$NODE" ]]; then
        echo "usage: node.sh <install|configure|format|start|stop|status|logs|purge> <node> [roles...]" >&2
        exit 2
    fi
    shift 2
    export JAVA_HOME HADOOP_HOME

    case "$action" in
        install)   do_install ;;
        configure) do_configure ;;
        format)    do_format ;;
        start)     do_start "$@" ;;
        stop)      do_stop "$@" ;;
        status)    do_status ;;
        logs)      do_logs ;;
        purge)     do_purge ;;
        *)         echo "неизвестное действие: $action" >&2; exit 2 ;;
    esac
}

main "$@"
