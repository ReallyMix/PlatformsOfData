#!/usr/bin/env bash
# Шаг 1. Скачивание JDK (Eclipse Temurin) и Hadoop с проверкой контрольных сумм.
# Внутренним узлам интернет не нужен: архивы раздаются с edge через scp.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Шаг 1/5: загрузка дистрибутивов в $DIST_DIR"
mkdir -p "$DIST_DIR"

# --- JDK ---
case "$(uname -m)" in
    x86_64)  jarch=x64 ;;
    aarch64) jarch=aarch64 ;;
    *)       die "неподдерживаемая архитектура $(uname -m)" ;;
esac
jdk="$DIST_DIR/jdk-$JAVA_MAJOR.tar.gz"
meta_url="https://api.adoptium.net/v3/assets/latest/$JAVA_MAJOR/hotspot?architecture=$jarch&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=linux&vendor=eclipse"
metadata="$(curl -fsSL --max-time 30 "$meta_url" 2>/dev/null || true)"
jdk_url_field="$(grep -m1 -oE '"link"[[:space:]]*:[[:space:]]*"[^"]+"' <<< "$metadata" || true)"
jdk_sum_field="$(grep -m1 -oE '"checksum"[[:space:]]*:[[:space:]]*"[0-9A-Fa-f]{64}"' <<< "$metadata" || true)"
jdk_url="$(sed -E 's/^"link"[[:space:]]*:[[:space:]]*"([^"]+)"$/\1/' <<< "$jdk_url_field")"
jdk_expected="$(grep -oE '[0-9A-Fa-f]{64}' <<< "$jdk_sum_field" | tr 'A-F' 'a-f' || true)"

if [[ ! -s "$jdk" ]] || ! gzip -t "$jdk" 2>/dev/null; then
    [[ -n "$jdk_url" ]] || die "не удалось получить ссылку на Temurin JDK $JAVA_MAJOR"
    log "скачиваю Temurin JDK $JAVA_MAJOR ($jarch)"
    curl -fL --retry 3 --progress-bar -o "$jdk.part" "$jdk_url"
    gzip -t "$jdk.part" || die "архив JDK повреждён"
    mv "$jdk.part" "$jdk"
fi

if [[ -z "$jdk_expected" ]]; then
    [[ "${SKIP_CHECKSUM:-0}" == 1 ]] || die "не удалось получить SHA-256 JDK (SKIP_CHECKSUM=1 — пропустить проверку)"
    warn "проверка контрольной суммы JDK пропущена"
else
    jdk_actual="$(sha256sum "$jdk" | awk '{print $1}')"
    [[ "$jdk_actual" == "$jdk_expected" ]] || { rm -f "$jdk"; die "SHA-256 JDK не совпала, архив удалён"; }
    ok "JDK: $jdk (SHA-256 совпадает)"
fi

# --- Hadoop ---
name="hadoop-$HADOOP_VERSION.tar.gz"
tgz="$DIST_DIR/$name"
if [[ ! -s "$tgz" ]]; then
    for m in $HADOOP_MIRRORS; do
        url="$m/hadoop-$HADOOP_VERSION/$name"
        log "скачиваю $url (~1 ГБ)"
        rm -f "$tgz.part"
        if curl -fL --retry 3 --progress-bar -o "$tgz.part" "$url"; then
            mv "$tgz.part" "$tgz"
            break
        fi
        warn "не получилось с $m, пробую следующее зеркало"
    done
    [[ -s "$tgz" ]] || die "не удалось скачать $name ни с одного зеркала"
fi

log "проверка SHA-512 $name"
expected=""
for m in $HADOOP_MIRRORS; do
    expected="$(curl -fsSL --max-time 30 "$m/hadoop-$HADOOP_VERSION/$name.sha512" 2>/dev/null \
                | tr -d ' \r\n' | grep -oE '[0-9A-Fa-f]{128}' | head -n1 | tr 'A-F' 'a-f' || true)"
    if [[ -n "$expected" ]]; then break; fi
done
if [[ -z "$expected" ]]; then
    [[ "${SKIP_CHECKSUM:-0}" == 1 ]] || die "не удалось получить $name.sha512 (запустите с SKIP_CHECKSUM=1, чтобы пропустить)"
    warn "проверка контрольной суммы пропущена"
else
    actual="$(sha512sum "$tgz" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        rm -f "$tgz"
        die "контрольная сумма не совпала, архив удалён — запустите шаг ещё раз"
    fi
    ok "Hadoop: $tgz (SHA-512 совпадает)"
fi
