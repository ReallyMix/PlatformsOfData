#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0
expect() {
    if [[ "$2" == "$3" ]]; then ok "$1 = $2"; else echo "${C_R}FAIL${C_0} $1 = ${2:-нет данных} (ожидалось $3)"; fail=1; fi
}

log "Шаг 4/4: проверка YARN и веб-интерфейсов"
build_yarn_node_script
for h in $(all_hosts); do push_yarn "$h"; done

echo; log "1. Демоны YARN на узлах"
for h in $(all_hosts); do yarn_do "$h" status || fail=1; done

echo; log "2. Состояние по данным ResourceManager (JMX)"
expected="$(count_words $NODEMANAGER_HOSTS)"
expect "Active NodeManagers"         "$(rm_metric NumActiveNMs || true)"         "$expected"
expect "Lost NodeManagers"           "$(rm_metric NumLostNMs || true)"           0
expect "Unhealthy NodeManagers"      "$(rm_metric NumUnhealthyNMs || true)"      0
expect "Decommissioned NodeManagers" "$(rm_metric NumDecommissionedNMs || true)" 0
yarn_cmd node -list 2>/dev/null | sed 's/^/    /' || true

echo; log "3. Тестовая задача MapReduce: pi (3 map-задачи по 1000 точек)"
examples="$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-$HADOOP_VERSION.jar"
job_out="$(yarn_cmd jar "$examples" pi 3 1000 2>&1 || true)"
app_id="$(grep -oE 'application_[0-9]+_[0-9]+' <<< "$job_out" | head -n1 || true)"
job_id="${app_id/application_/job_}"
grep -E 'Estimated value of Pi|completed successfully|Running job' <<< "$job_out" | sed 's/^/    /' || true
if [[ -z "$app_id" ]]; then
    echo "${C_R}FAIL${C_0} задача не была отправлена в YARN, последние строки вывода:"
    tail -n 20 <<< "$job_out"
    fail=1
else
    expect "Final-State $app_id" \
        "$(yarn_cmd application -status "$app_id" 2>/dev/null | awk -F': *' '/Final-State/{print $2}' | tr -d ' ' || true)" SUCCEEDED

    jhs_state=""
    for _ in $(seq 1 30); do
        jhs_state="$(curl -fsS --max-time 10 "http://$HISTORYSERVER_HOST:$JHS_HTTP_PORT/ws/v1/history/mapreduce/jobs/$job_id" 2>/dev/null \
                     | grep -oE '"state" *: *"[A-Z]+"' | head -n1 | grep -oE '[A-Z]+' || true)"
        if [[ -n "$jhs_state" ]]; then break; fi
        sleep 2
    done
    expect "задача $job_id в JobHistory" "$jhs_state" SUCCEEDED
fi

echo; log "4. Веб-интерфейсы через nginx на $EDGE_HOST"
if [[ "$WEB_AUTH" == yes ]]; then auth=(-u "$WEB_USER:$(web_password)"); else auth=(); fi
for entry in $WEB_UI; do
    IFS=: read -r name ext _ _ <<< "$entry"
    url="http://127.0.0.1:$ext/"
    expect "$name :$ext" "$(curl -sL -o /dev/null -w '%{http_code}' --max-time 15 "${auth[@]}" "$url" || true)" 200
done

rm_ext="$(awk -F: '$1 == "resourcemanager" {print $2}' <<< "$WEB_UI")"
if [[ "$WEB_AUTH" == yes ]]; then
    expect "без пароля на :$rm_ext" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://127.0.0.1:$rm_ext/cluster" || true)" 401
fi
expect "POST к REST API на :$rm_ext" \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${auth[@]}" -X POST "http://127.0.0.1:$rm_ext/ws/v1/cluster/apps/new-application" || true)" 403

echo; log "5. Логи демонов YARN (ERROR/FATAL)"
for h in $(all_hosts); do
    rc=0
    yarn_do "$h" logs || rc=$?
    case $rc in
        0) ;;
        3) warn "$h: в логах есть ERROR — посмотрите вывод выше" ;;
        2) echo "${C_R}FAIL${C_0} $h: в логах есть FATAL"; fail=1 ;;
        *) echo "${C_R}FAIL${C_0} $h: не удалось проверить логи (код $rc)"; fail=1 ;;
    esac
done

echo
if (( fail )); then
    die "проверка не пройдена — см. строки FAIL/WARN выше"
fi
ok "YARN работает: ResourceManager, $expected NodeManager и JobHistory Server, тестовая задача выполнена, веб-интерфейсы опубликованы"
echo
echo "Веб-интерфейсы (логин $WEB_USER, пароль: cat $SECRETS_DIR/web-password):"
for entry in $WEB_UI; do
    IFS=: read -r name ext _ _ <<< "$entry"
    printf '    %-20s http://%s:%s/\n' "$name" "$EDGE_PUBLIC_HOST" "$ext"
done
