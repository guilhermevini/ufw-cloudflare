#!/usr/bin/env bash
# Runs ufw-cloudflare against the real ufw. Needs root and changes the firewall rules, so only
# run it in a throwaway machine or container (CI runs it on a GitHub-hosted runner).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    ufw show added >&2
    exit 1
}

sync() {
    "$root/ufw-cloudflare" --source file --ipv4-file "$tmp/v4" --ipv6-file "$tmp/v6" "$@"
}

managed() {
    ufw show added | grep -c "comment 'cloudflare'" || true
}

cp "$root/list_ipv4.txt" "$tmp/v4"
cp "$root/list_ipv6.txt" "$tmp/v6"
total=$(($(wc -l < "$tmp/v4") + $(wc -l < "$tmp/v6")))
ufw allow 22/tcp > /dev/null

echo '== first run'
sync
[ "$(managed)" -eq "$total" ] || fail "expected $total managed rules"

echo '== second run is a no-op'
out=$(sync)
echo "$out"
[ "$(grep -c 'Already up to date' <<< "$out")" -eq 2 ] || fail "second run changed rules"

echo '== ports given in another order are still up to date'
out=$(sync --ports 443,80)
[ "$(grep -c 'Already up to date' <<< "$out")" -eq 2 ] || fail "port order caused changes"

echo '== a removed range is deleted'
removed=$(head -1 "$tmp/v4")
sed -i 1d "$tmp/v4"
sync
[ "$(managed)" -eq "$((total - 1))" ] || fail "range was not deleted"
! ufw show added | grep -qF "from $removed " || fail "$removed is still allowed"

echo '== changing the ports replaces the rules'
sync --ports 443
[ "$(managed)" -eq "$((total - 1))" ] || fail "wrong number of rules after changing ports"
! ufw show added | grep -q '80,443' || fail "old port rules are still there"

echo '== --remove deletes only the managed rules'
sync --remove
[ "$(managed)" -eq 0 ] || fail "managed rules left after --remove"
ufw show added | grep -qx 'ufw allow 22/tcp' || fail "unrelated rule was deleted"

echo 'All integration tests passed.'
