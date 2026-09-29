#!/usr/bin/env bash
# Общие функции для скриптов развёртывания. Все скрипты запускаются на edge-ноде
# под пользователем team; на внутренние узлы ходим по ssh с ключом team_internal.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT_DIR/config.env"

# shellcheck disable=SC2034
DIST_DIR="$ROOT_DIR/dist"          # скачанные архивы JDK и Hadoop
BUILD_DIR="$ROOT_DIR/build"        # сгенерированные конфиги и node.sh
REMOTE_STAGE="/tmp/hdfs-deploy"    # куда кладём файлы на узлах

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
          -o BatchMode=yes -o LogLevel=ERROR)

if [[ -t 1 ]]; then
    C_B=$'\033[1;34m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_R=$'\033[1;31m'; C_0=$'\033[0m'
else
    C_B=""; C_G=""; C_Y=""; C_R=""; C_0=""
fi
log()  { echo "${C_B}==>${C_0} $*"; }
ok()   { echo "${C_G} OK${C_0} $*"; }
warn() { echo "${C_Y}WARN${C_0} $*" >&2; }
die()  { echo "${C_R}FAIL${C_0} $*" >&2; exit 1; }

all_hosts()   { local e; for e in $CLUSTER_HOSTS; do echo "${e%%:*}"; done; }
host_ip()     { local e; for e in $CLUSTER_HOSTS; do if [[ "${e%%:*}" == "$1" ]]; then echo "${e##*:}"; return 0; fi; done; return 1; }
is_local()    { [[ "$1" == "$EDGE_HOST" ]]; }
count_words() { echo $#; }

# on <узел> <команда> — выполнить команду на узле от имени $SSH_USER
on() {
    local host=$1; shift
    if is_local "$host"; then
        bash -c "$*"
    else
        ssh -n "${SSH_OPTS[@]}" "$SSH_USER@$host" "$*"
    fi
}

# copy_to <узел> <каталог-назначения> <файлы...>
copy_to() {
    local host=$1 dst=$2; shift 2
    on "$host" "mkdir -p '$dst'"
    if is_local "$host"; then
        cp -f "$@" "$dst/"
    else
        scp -q "${SSH_OPTS[@]}" "$@" "$SSH_USER@$host:$dst/"
    fi
}

# Собирает build/node.sh = config.env + remote/node.sh
build_node_script() {
    mkdir -p "$BUILD_DIR"
    {
        echo '#!/usr/bin/env bash'
        echo "# Сгенерировано $(date '+%F %T') из config.env + remote/node.sh — не редактировать"
        cat "$ROOT_DIR/config.env"
        echo
        cat "$ROOT_DIR/remote/node.sh"
    } > "$BUILD_DIR/node.sh"
}

# Кладёт на узел свежий node.sh и (если уже сгенерированы) конфиги
push_node() {
    local host=$1
    copy_to "$host" "$REMOTE_STAGE" "$BUILD_DIR/node.sh"
    if [[ -d "$BUILD_DIR/conf" ]]; then
        copy_to "$host" "$REMOTE_STAGE/conf" "$BUILD_DIR"/conf/*
    fi
}

# node_do <узел> <действие> [аргументы] — выполнить действие remote/node.sh от root
node_do() {
    local host=$1; shift
    on "$host" "sudo bash $REMOTE_STAGE/node.sh $1 $host ${*:2}"
}

# Подставляет значения из config.env в шаблоны templates/* -> build/conf/*
render_configs() {
    local out="$BUILD_DIR/conf" f v
    local vars="NAMENODE_HOST SECONDARY_NAMENODE_HOST NN_RPC_PORT NN_HTTP_PORT SNN_HTTP_PORT
                DFS_REPLICATION DATA_DIR LOG_DIR PID_DIR JAVA_HOME HADOOP_HOME HADOOP_USER HADOOP_VERSION"
    local args=()
    for v in $vars; do args+=(-e "s|@${v}@|${!v}|g"); done

    rm -rf "$out"
    mkdir -p "$out"
    for f in core-site.xml hdfs-site.xml hadoop-env.sh "hadoop-hdfs@.service"; do
        sed "${args[@]}" "$ROOT_DIR/templates/$f" > "$out/$f"
        if grep -q '@[A-Z_]\{2,\}@' "$out/$f"; then die "в $f остались незаменённые плейсхолдеры"; fi
    done
    tr ' ' '\n' <<< "$DATANODE_HOSTS" | sed '/^$/d' > "$out/workers"
}

# hdfs_admin <аргументы hdfs> — команда hdfs на edge от имени суперпользователя HDFS
hdfs_admin() {
    ( cd / && sudo -u "$HADOOP_USER" "$HADOOP_HOME/bin/hdfs" "$@" )
}

# nn_metric <bean> <ключ> — числовая метрика NameNode из JMX
nn_metric() {
    local json
    json="$(curl -fsS --max-time 10 "http://${NAMENODE_HOST}:${NN_HTTP_PORT}/jmx?qry=Hadoop:service=NameNode,name=$1")" || return 1
    grep -oE "\"$2\" *: *[0-9]+" <<< "$json" | grep -oE '[0-9]+$'
}

# wait_port <узел> <порт> [секунд]
wait_port() {
    local host=$1 port=$2 limit=${3:-60} i
    for (( i = 0; i < limit; i += 2 )); do
        if timeout 2 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then return 0; fi
        sleep 2
    done
    return 1
}
