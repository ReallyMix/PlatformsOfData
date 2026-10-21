#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

wait_port() {
    for i in $(seq 1 $2); do
        if ss -tln | grep -q ":$1 "; then
            return 0
        fi
        sleep 2
    done
    return 1
}

echo "=== запуск Hive Metastore"
sudo systemctl enable hive@metastore
sudo systemctl restart hive@metastore
if ! wait_port 9083 60; then
    sudo journalctl -u hive@metastore -n 30 --no-pager
    echo "Metastore не запустился"
    exit 1
fi
echo "Metastore слушает порт 9083"

echo "=== запуск HiveServer2 (это может занять пару минут)"
sudo systemctl enable hive@hiveserver2
sudo systemctl restart hive@hiveserver2
if ! wait_port 10000 120; then
    sudo journalctl -u hive@hiveserver2 -n 30 --no-pager
    echo "HiveServer2 не запустился"
    exit 1
fi
echo "HiveServer2 слушает порт 10000"
