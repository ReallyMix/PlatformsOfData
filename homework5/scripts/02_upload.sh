#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"

PY4J_ZIP=$(ls $SPARK_HOME/python/lib/py4j-*-src.zip)
export PYTHONPATH=$SPARK_HOME/python:$PY4J_ZIP
export PYSPARK_PYTHON=python3

echo "=== запуск потока Prefect"
cd "$ROOT"
.venv/bin/python flow.py
