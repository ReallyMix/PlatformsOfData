#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== загрузка исходных данных в HDFS"
$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/prefect/input
$HADOOP_HOME/bin/hdfs dfs -put -f "$ROOT/data/trips.csv" /user/prefect/input/trips.csv
$HADOOP_HOME/bin/hdfs dfs -ls /user/prefect/input
