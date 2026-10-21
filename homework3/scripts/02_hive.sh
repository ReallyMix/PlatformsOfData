#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== установка Hive $HIVE_VERSION"
HIVE_DIR=/opt/apache-hive-$HIVE_VERSION-bin

if [ ! -d "$HIVE_DIR" ]; then
    mkdir -p "$ROOT/dist"
    if [ ! -f "$ROOT/dist/hive.tar.gz" ]; then
        curl -fL --progress-bar -o "$ROOT/dist/hive.tar.gz.part" "$HIVE_URL"
        mv "$ROOT/dist/hive.tar.gz.part" "$ROOT/dist/hive.tar.gz"
    fi
    sudo tar -xzf "$ROOT/dist/hive.tar.gz" -C /opt
fi
sudo ln -sfn "$HIVE_DIR" "$HIVE_HOME"

sudo rm -f $HIVE_HOME/lib/guava-*.jar
sudo cp $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar $HIVE_HOME/lib/
sudo cp $HADOOP_HOME/share/hadoop/common/lib/failureaccess-*.jar $HIVE_HOME/lib/ 2>/dev/null || true
sudo ln -sf /usr/share/java/postgresql.jar $HIVE_HOME/lib/postgresql.jar

sed -e "s|@HIVE_HOST@|$HIVE_HOST|g" \
    -e "s|@DB_NAME@|$DB_NAME|g" \
    -e "s|@DB_USER@|$DB_USER|g" \
    -e "s|@DB_PASS@|$DB_PASS|g" \
    "$ROOT/conf/hive-site.xml" | sudo tee $HIVE_HOME/conf/hive-site.xml > /dev/null
sudo chown -R $HADOOP_USER:$HADOOP_USER "$HIVE_DIR"

echo "=== каталоги в HDFS"
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/hive/warehouse /tmp/hive
sudo -u $HADOOP_USER $HADOOP_HOME/bin/hdfs dfs -chmod 777 /tmp/hive

echo "=== схема Metastore в PostgreSQL"
HIVE_ENV="JAVA_HOME=$JAVA_HOME HADOOP_HOME=$HADOOP_HOME HIVE_HOME=$HIVE_HOME"
if sudo -u $HADOOP_USER env $HIVE_ENV $HIVE_HOME/bin/schematool -dbType postgres -info > /dev/null 2>&1; then
    echo "схема уже создана"
else
    sudo -u $HADOOP_USER env $HIVE_ENV $HIVE_HOME/bin/schematool -dbType postgres -initSchema
fi

echo "=== службы systemd"
sudo tee /etc/systemd/system/hive@.service > /dev/null <<UNIT
[Unit]
Description=Apache Hive %i
After=network-online.target postgresql.service

[Service]
User=$HADOOP_USER
Environment=JAVA_HOME=$JAVA_HOME
Environment=HADOOP_HOME=$HADOOP_HOME
Environment=HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
Environment=HIVE_HOME=$HIVE_HOME
Environment=HIVE_CONF_DIR=$HIVE_HOME/conf
ExecStart=$HIVE_HOME/bin/hive --service %i
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload

echo "Hive установлен в $HIVE_HOME"
