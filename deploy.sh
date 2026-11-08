#!/usr/bin/env bash
# Kept for backward compatibility: applies the lists in this repository. Prefer ./ufw-cloudflare (see README).
set -euo pipefail

cd "$(dirname "$0")"
exec ./ufw-cloudflare --source file "$@"
