#!/bin/bash
set -eo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== запуск задачи Spark в YARN"
$SPARK_HOME/bin/spark-submit "$ROOT/job.py" 2>&1 | grep -v -E "^[0-9/: ]+(INFO|WARN)|^SLF4J"
