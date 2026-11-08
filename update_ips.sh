#!/usr/bin/env bash
# Refresh list_ipv4.txt and list_ipv6.txt from the official Cloudflare lists.
set -euo pipefail

cd "$(dirname "$0")"

for v in 4 6; do
    tmp="$(mktemp)"
    curl -fsSL --retry 3 "https://www.cloudflare.com/ips-v${v}" -o "$tmp"
    # Make sure the content looks like a CIDR list before overwriting the file
    if [ ! -s "$tmp" ] || grep -qvE '^[0-9A-Fa-f:.]+/[0-9]+$|^$' "$tmp"; then
        echo "Unexpected content in ips-v${v}; file not updated." >&2
        rm -f "$tmp"
        exit 1
    fi
    grep -v '^$' "$tmp" | LC_ALL=C sort -u -V > "list_ipv${v}.txt"
    rm -f "$tmp"
    echo "list_ipv${v}.txt: $(wc -l < "list_ipv${v}.txt" | tr -d ' ') ranges"
done
