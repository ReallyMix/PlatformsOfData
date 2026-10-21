#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
cd /

echo "=== PostgreSQL для Hive Metastore"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql libpostgresql-jdbc-java > /dev/null
sudo systemctl enable --now postgresql

if ! sudo -u postgres psql -tAc "select 1 from pg_roles where rolname='$DB_USER'" | grep -q 1; then
    sudo -u postgres psql -c "create user $DB_USER with password '$DB_PASS'"
fi
if ! sudo -u postgres psql -tAc "select 1 from pg_database where datname='$DB_NAME'" | grep -q 1; then
    sudo -u postgres psql -c "create database $DB_NAME owner $DB_USER"
fi

echo "PostgreSQL готов: база $DB_NAME, пользователь $DB_USER"
