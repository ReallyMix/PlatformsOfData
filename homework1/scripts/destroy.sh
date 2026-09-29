#!/usr/bin/env bash
# Полное удаление HDFS со всех узлов, ВКЛЮЧАЯ ДАННЫЕ. Нужно, чтобы развернуть всё с нуля.
#   scripts/destroy.sh          — спросит подтверждение
#   scripts/destroy.sh --yes    — без вопросов
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "Удалить HDFS и ВСЕ ДАННЫЕ на узлах $(all_hosts | tr '\n' ' ')? Введите '$CLUSTER_ID': " answer
    [[ "$answer" == "$CLUSTER_ID" ]] || die "отменено"
fi

build_node_script
for h in $(all_hosts); do
    push_node "$h"
    node_do "$h" purge
    on "$h" "rm -rf $REMOTE_STAGE"
done
ok "HDFS удалён со всех узлов (архивы в $DIST_DIR сохранены)"
