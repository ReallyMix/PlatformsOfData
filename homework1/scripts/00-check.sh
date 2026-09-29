#!/usr/bin/env bash
# Шаг 0. Проверка окружения: ключ, SSH и sudo на всех узлах, ресурсы, интернет на edge.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 0/5: проверка окружения"

if [[ "$(hostname -s)" != "$EDGE_HOST" ]]; then
    warn "скрипты рассчитаны на запуск с $EDGE_HOST, текущий узел: $(hostname -s)"
fi
[[ -r "$SSH_KEY" ]] || die "не найден SSH-ключ $SSH_KEY"
for cmd in ssh scp curl tar gzip sha256sum sha512sum awk sed timeout; do
    command -v "$cmd" >/dev/null || die "на edge нет утилиты $cmd"
done

edge_arch="$(uname -m)"
printf '%-12s %-13s %-8s %-4s %-8s %-10s %s\n' HOST IP ARCH CPU RAM_MB ROOT_FREE OS
for h in $(all_hosts); do
    ip="$(host_ip "$h")"
    if ! on "$h" 'sudo -n true' >/dev/null 2>&1; then
        die "$h: нет доступа по SSH или sudo требует пароль"
    fi
    mapfile -t info < <(on "$h" 'hostname -s; uname -m; nproc; free -m | awk "/^Mem:/{print \$2}"; df -Pm / | awk "NR==2{print \$4}"; . /etc/os-release && echo "$PRETTY_NAME"')
    printf '%-12s %-13s %-8s %-4s %-8s %-10s %s\n' "$h" "$ip" "${info[1]}" "${info[2]}" "${info[3]}" "${info[4]}MB" "${info[5]}"

    [[ "${info[1]}" == "$edge_arch" ]] || die "$h: архитектура ${info[1]} отличается от edge ($edge_arch)"
    if [[ "${info[0]}" != "$h" ]]; then warn "$h: hostname узла = ${info[0]} (не критично, адреса задаются через /etc/hosts)"; fi
    if (( info[4] < 4000 )); then warn "$h: на / свободно меньше 4 ГБ"; fi
done

if curl -fsI --max-time 15 https://archive.apache.org/ >/dev/null 2>&1; then
    ok "edge имеет доступ в интернет"
else
    warn "с edge нет доступа к archive.apache.org — положите архивы в dist/ вручную (см. README)"
fi
ok "окружение в порядке: SSH и sudo работают на всех узлах"
