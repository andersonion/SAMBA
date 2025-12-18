#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-samba-py}"
ENV_PREFIX="${ENV_PREFIX:-$(pwd)/.envs/${ENV_NAME}}"

conda run -p "$ENV_PREFIX" pytest -q
