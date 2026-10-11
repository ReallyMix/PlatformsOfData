#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 3/4: публикация веб-интерфейсов через nginx на $EDGE_HOST"
is_local "$(hostname -s)" || die "этот шаг выполняется только на $EDGE_HOST"

if ! command -v nginx >/dev/null; then
    log "установка nginx"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null
fi
ok "$(nginx -v 2>&1)"

render_nginx_conf

if [[ "$WEB_AUTH" == yes ]]; then
    pass="$(web_password)"
    printf '%s:%s\n' "$WEB_USER" "$(openssl passwd -apr1 "$pass")" | sudo tee "$NGINX_HTPASSWD" >/dev/null
    sudo chown root:www-data "$NGINX_HTPASSWD"
    sudo chmod 640 "$NGINX_HTPASSWD"
    ok "basic auth: пользователь $WEB_USER, пароль в $SECRETS_DIR/web-password"
else
    warn "WEB_AUTH=no — веб-интерфейсы будут открыты без пароля"
fi

sudo install -m 644 "$YARN_BUILD_DIR/nginx/hadoop-ui.conf" "$NGINX_CONF"
if ! sudo nginx -t 2>/tmp/nginx-test.log; then
    cat /tmp/nginx-test.log >&2
    die "nginx -t: ошибка в конфигурации"
fi
sudo systemctl enable --quiet nginx
sudo systemctl restart nginx
ok "nginx перезапущен с конфигом $NGINX_CONF"

if sudo ufw status 2>/dev/null | grep -q 'Status: active'; then
    for p in $(web_ports); do sudo ufw allow "$p/tcp" >/dev/null; done
    ok "порты открыты в ufw: $(web_ports | tr '\n' ' ')"
fi

echo
log "опубликованные веб-интерфейсы:"
for entry in $WEB_UI; do
    IFS=: read -r name ext host port <<< "$entry"
    printf '    %-20s http://%s:%s/   (%s:%s)\n' "$name" "$EDGE_PUBLIC_HOST" "$ext" "$host" "$port"
done
