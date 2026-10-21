#!/bin/bash
set -eo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== партиции в HDFS"
$HADOOP_HOME/bin/hdfs dfs -ls /user/hive/warehouse/shop.db/sales_daily

echo "=== чтение таблицы клиентом Hive (beeline)"
$HIVE_HOME/bin/beeline -u "$JDBC_URL" -n $HADOOP_USER --silent=true -f "$ROOT/sql/check.sql" 2>&1 | grep -v -E "^(SLF4J|WARN|INFO)"
