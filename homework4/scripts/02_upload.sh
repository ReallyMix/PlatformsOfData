#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== загрузка исходных данных в HDFS"
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/spark/input
$HADOOP_HOME/bin/hdfs dfs -put -f "$ROOT/data/sales.csv" /user/spark/input/sales.csv
$HADOOP_HOME/bin/hdfs dfs -ls /user/spark/input
