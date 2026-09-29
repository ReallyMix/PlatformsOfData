#!/usr/bin/env bash
# Шаг 2. Установка на все узлы: /etc/hosts, пользователь hadoop, Java, Hadoop, каталоги.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 2/5: установка Java и Hadoop на все узлы"
jdk="$DIST_DIR/jdk-$JAVA_MAJOR.tar.gz"
hadoop="$DIST_DIR/hadoop-$HADOOP_VERSION.tar.gz"
[[ -s "$jdk" && -s "$hadoop" ]] || die "нет архивов в $DIST_DIR — сначала scripts/01-download.sh"

build_node_script
for h in $(all_hosts); do
    log "[$h] установка"
    push_node "$h"
    if is_local "$h"; then
        rm -rf "$REMOTE_STAGE/dist"
        ln -s "$DIST_DIR" "$REMOTE_STAGE/dist"
    elif on "$h" "test -x $INSTALL_DIR/hadoop-$HADOOP_VERSION/bin/hdfs && test -x $INSTALL_DIR/jdk-$JAVA_MAJOR/bin/java"; then
        log "[$h] Java и Hadoop уже установлены, копирование архивов пропущено"
    else
        log "[$h] копирование архивов"
        copy_to "$h" "$REMOTE_STAGE/dist" "$jdk" "$hadoop"
    fi

    node_do "$h" install

    if ! is_local "$h"; then on "$h" "rm -rf $REMOTE_STAGE/dist"; fi
    ok "[$h] готово"
done
