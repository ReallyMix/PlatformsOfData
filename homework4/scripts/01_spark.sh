#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== установка Spark $SPARK_VERSION"
command -v python3 > /dev/null || sudo apt-get install -y -qq python3

SPARK_DIR=/opt/spark-$SPARK_VERSION-bin-hadoop3
if [ ! -d "$SPARK_DIR" ]; then
    mkdir -p "$ROOT/dist"
    if [ ! -f "$ROOT/dist/spark.tgz" ]; then
        curl -fL --progress-bar -o "$ROOT/dist/spark.tgz.part" "$SPARK_URL"
        mv "$ROOT/dist/spark.tgz.part" "$ROOT/dist/spark.tgz"
    fi
    sudo tar -xzf "$ROOT/dist/spark.tgz" -C /opt
fi
sudo ln -sfn "$SPARK_DIR" "$SPARK_HOME"

for f in spark-defaults.conf spark-env.sh hive-site.xml; do
    sed -e "s|@HDFS_URL@|$HDFS_URL|g" \
        -e "s|@JAVA_HOME@|$JAVA_HOME|g" \
        -e "s|@HADOOP_HOME@|$HADOOP_HOME|g" \
        -e "s|@METASTORE_URI@|$METASTORE_URI|g" \
        "$ROOT/conf/$f" | sudo tee "$SPARK_HOME/conf/$f" > /dev/null
done

echo "=== библиотеки Spark в HDFS"
if $HADOOP_HOME/bin/hdfs dfs -test -d /spark/jars; then
    echo "уже загружены"
else
    $HADOOP_HOME/bin/hdfs dfs -mkdir -p /spark/jars
    $HADOOP_HOME/bin/hdfs dfs -put $SPARK_HOME/jars/* /spark/jars/
fi

echo "Spark установлен в $SPARK_HOME"
