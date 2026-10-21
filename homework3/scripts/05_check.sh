#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== службы"
systemctl is-active postgresql hive@metastore hive@hiveserver2

echo "=== два клиента подключаются к HiveServer2 одновременно"
$HIVE_HOME/bin/beeline -u "$JDBC_URL" -n client1 --silent=true \
    -e "select order_date, count(*) as orders, round(sum(price * quantity), 2) as revenue from shop.orders group by order_date order by order_date;" \
    > /tmp/hive_client1.log 2>&1 &
$HIVE_HOME/bin/beeline -u "$JDBC_URL" -n client2 --silent=true \
    -e "show partitions shop.orders;" \
    > /tmp/hive_client2.log 2>&1 &
wait

echo "--- client1:"
grep -v -E "^(SLF4J|WARN|INFO)" /tmp/hive_client1.log || true
echo "--- client2:"
grep -v -E "^(SLF4J|WARN|INFO)" /tmp/hive_client2.log || true

echo "=== партиции в HDFS"
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -ls /user/hive/warehouse/shop.db/orders

echo "=== метаданные в PostgreSQL"
sudo -u postgres psql -d $DB_NAME -c 'select "TBL_NAME", "TBL_TYPE" from "TBLS"'
sudo -u postgres psql -d $DB_NAME -c 'select "PART_NAME" from "PARTITIONS" order by 1'
