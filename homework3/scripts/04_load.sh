#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== загрузка CSV в HDFS"
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hive/raw/orders
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -put -f - /user/hive/raw/orders/orders.csv < "$ROOT/data/orders.csv"
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -ls /user/hive/raw/orders

echo "=== загрузка в партиционированную таблицу shop.orders"
$HIVE_HOME/bin/beeline -u "$JDBC_URL" -n $HADOOP_USER -f "$ROOT/sql/load.sql"
