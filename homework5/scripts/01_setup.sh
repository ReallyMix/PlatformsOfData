#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"

echo "=== проверка Spark из ДЗ №4"
if [ ! -x "$SPARK_HOME/bin/spark-submit" ]; then
    echo "Spark не найден в $SPARK_HOME, сначала выполните homework4/deploy.sh"
    exit 1
fi

echo "=== виртуальное окружение Python и Prefect"
sudo apt-get install -y -qq python3-venv > /dev/null
if [ ! -d "$ROOT/.venv" ]; then
    python3 -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/pip" install -q --upgrade pip
"$ROOT/.venv/bin/pip" install -q -r "$ROOT/requirements.txt"
"$ROOT/.venv/bin/prefect" version
