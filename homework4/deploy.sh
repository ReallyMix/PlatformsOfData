#!/bin/bash
set -e
cd "$(dirname "$0")"

bash scripts/01_spark.sh
bash scripts/02_upload.sh
bash scripts/03_run.sh
bash scripts/04_check_hive.sh
