#!/bin/bash
set -e
cd "$(dirname "$0")"

bash scripts/01_postgres.sh
bash scripts/02_hive.sh
bash scripts/03_start.sh
bash scripts/04_load.sh
bash scripts/05_check.sh
