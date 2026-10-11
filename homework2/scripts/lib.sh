#!/usr/bin/env bash

HW2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HW1_DIR="$HW2_DIR/../homework1"
if [[ ! -f "$HW1_DIR/scripts/lib.sh" ]]; then
    echo "FAIL не найден $HW1_DIR — ДЗ №2 использует скрипты и config.env из homework1" >&2
    exit 1
fi
HW1_DIR="$(cd "$HW1_DIR" && pwd)"

source "$HW1_DIR/scripts/lib.sh"
source "$HW2_DIR/config.env"

YARN_BUILD_DIR="$HW2_DIR/build"
YARN_STAGE="/tmp/yarn-deploy"
SECRETS_DIR="$HW2_DIR/.secrets"
NGINX_CONF="/etc/nginx/conf.d/hadoop-ui.conf"
NGINX_HTPASSWD="/etc/nginx/hadoop-ui.htpasswd"
AM_HEAP_MB=$(( AM_MEMORY_MB * 8 / 10 ))

build_yarn_node_script() {
    mkdir -p "$YARN_BUILD_DIR"
    {
        echo '#!/usr/bin/env bash'
        echo "# Сгенерировано $(date '+%F %T') — не редактировать"
        cat "$HW1_DIR/config.env"
        echo
        cat "$HW2_DIR/config.env"
        echo
        cat "$HW2_DIR/remote/node-yarn.sh"
    } > "$YARN_BUILD_DIR/node-yarn.sh"
}

push_yarn() {
    local host=$1
    copy_to "$host" "$YARN_STAGE" "$YARN_BUILD_DIR/node-yarn.sh"
    if [[ -d "$YARN_BUILD_DIR/conf" ]]; then
        copy_to "$host" "$YARN_STAGE/conf" "$YARN_BUILD_DIR"/conf/*
    fi
}

yarn_do() {
    local host=$1; shift
    on "$host" "sudo bash $YARN_STAGE/node-yarn.sh $1 $host ${*:2}"
}

render_yarn_configs() {
    local out="$YARN_BUILD_DIR/conf" f v
    local vars="RESOURCEMANAGER_HOST HISTORYSERVER_HOST RM_RPC_PORT RM_HTTP_PORT JHS_RPC_PORT JHS_HTTP_PORT
                NM_MEMORY_MB NM_VCORES AM_MEMORY_MB AM_HEAP_MB MAP_MEMORY_MB REDUCE_MEMORY_MB
                DATA_DIR LOG_DIR PID_DIR HADOOP_HOME HADOOP_USER HADOOP_VERSION"
    local args=()
    for v in $vars; do args+=(-e "s|@${v}@|${!v}|g"); done

    rm -rf "$out"
    mkdir -p "$out"
    for f in yarn-site.xml mapred-site.xml "hadoop-yarn@.service" "hadoop-mapred@.service"; do
        sed "${args[@]}" "$HW2_DIR/templates/$f" > "$out/$f"
        if grep -q '@[A-Z_]\{2,\}@' "$out/$f"; then die "в $f остались незаменённые плейсхолдеры"; fi
    done
}

render_nginx_conf() {
    local out="$YARN_BUILD_DIR/nginx/hadoop-ui.conf" entry name ext host port auth=""
    mkdir -p "$(dirname "$out")"
    if [[ "$WEB_AUTH" == yes ]]; then
        auth="    auth_basic \"Hadoop $CLUSTER_ID\";
    auth_basic_user_file $NGINX_HTPASSWD;"
    fi
    {
        echo "# Сгенерировано homework2/scripts/03-publish.sh — не редактировать вручную"
        echo "# Веб-интерфейсы демонов кластера $CLUSTER_ID, опубликованные на $EDGE_PUBLIC_HOST"
        echo
        echo "server_tokens off;"
        for entry in $WEB_UI; do
            IFS=: read -r name ext host port <<< "$entry"
            cat <<CONF

# $name: http://$EDGE_PUBLIC_HOST:$ext/ -> $host:$port
server {
    listen $ext;
    server_name _;
$auth

    location / {
        # Только просмотр: изменяющие запросы (POST/PUT/DELETE) к REST API запрещены
        limit_except GET HEAD { deny all; }

        proxy_pass http://$host:$port;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
}
CONF
        done
    } > "$out"
}

web_password() {
    local file="$SECRETS_DIR/web-password"
    if [[ ! -s "$file" ]]; then
        mkdir -p "$SECRETS_DIR"
        chmod 700 "$SECRETS_DIR"
        openssl rand -base64 18 | tr -d '/+=\n' | cut -c1-16 > "$file"
        chmod 600 "$file"
    fi
    cat "$file"
}

web_ports() { local e; for e in $WEB_UI; do echo "$e" | cut -d: -f2; done; }

yarn_cmd()   { ( cd / && sudo -u "$HADOOP_USER" "$HADOOP_HOME/bin/yarn" "$@" ); }
mapred_cmd() { ( cd / && sudo -u "$HADOOP_USER" "$HADOOP_HOME/bin/mapred" "$@" ); }

rm_metric() {
    local json
    json="$(curl -fsS --max-time 10 "http://${RESOURCEMANAGER_HOST}:${RM_HTTP_PORT}/jmx?qry=Hadoop:service=ResourceManager,name=ClusterMetrics")" || return 1
    grep -oE "\"$1\" *: *[0-9]+" <<< "$json" | grep -oE '[0-9]+$'
}
