#!/bin/bash
set -e
cd "$(dirname "$0")"

bash scripts/01_setup.sh
bash scripts/02_upload.sh
bash scripts/03_run_flow.sh
