#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "Удалить YARN с узлов $(all_hosts | tr '\n' ' ')и публикацию веб-интерфейсов? Введите '$CLUSTER_ID': " answer
    [[ "$answer" == "$CLUSTER_ID" ]] || die "отменено"
fi

build_yarn_node_script
for h in $(all_hosts); do
    copy_to "$h" "$YARN_STAGE" "$YARN_BUILD_DIR/node-yarn.sh"
    yarn_do "$h" purge
    on "$h" "rm -rf $YARN_STAGE"
done

sudo rm -f "$NGINX_CONF" "$NGINX_HTPASSWD"
if command -v nginx >/dev/null && sudo nginx -t 2>/dev/null; then sudo systemctl reload nginx; fi
rm -rf "$SECRETS_DIR" "$YARN_BUILD_DIR"
ok "YARN и публикация веб-интерфейсов удалены (HDFS работает как раньше; nginx оставлен установленным)"
