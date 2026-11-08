#!/usr/bin/env bats
# Unit tests: ufw and curl are replaced by the stubs in tests/bin, so they need no root.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PATH="$BATS_TEST_DIRNAME/bin:$PATH"
    export UFW_STUB_RULES="$BATS_TEST_TMPDIR/rules" UFW_STUB_LOG="$BATS_TEST_TMPDIR/log"
    export CURL_STUB_DIR="$BATS_TEST_TMPDIR/www"
    mkdir -p "$CURL_STUB_DIR"
    printf '173.245.48.0/20\n103.21.244.0/22\n' > "$CURL_STUB_DIR/ips-v4"
    printf '2400:cb00::/32\n' > "$CURL_STUB_DIR/ips-v6"
    cd "$BATS_TEST_TMPDIR"
}

run_script() {
    run "$ROOT/ufw-cloudflare" "$@"
}

rules() {
    cat "$UFW_STUB_RULES"
}

@test "adds one tagged rule per range on the first run" {
    run_script
    [ "$status" -eq 0 ]
    [[ $output == *"[IPv4] 2 Cloudflare ranges, port 80,443/tcp: +2 / -0"* ]]
    [[ $output == *"[IPv6] 1 Cloudflare ranges, port 80,443/tcp: +1 / -0"* ]]
    [ "$(rules | wc -l)" -eq 3 ]
    grep -qxF "ufw allow from 173.245.48.0/20 to any port 80,443 proto tcp comment 'cloudflare'" "$UFW_STUB_RULES"
    grep -qxF "ufw allow from 2400:cb00::/32 to any port 80,443 proto tcp comment 'cloudflare'" "$UFW_STUB_RULES"
}

@test "is idempotent" {
    run_script
    : > "$UFW_STUB_LOG"
    run_script
    [ "$status" -eq 0 ]
    [[ $output == *"[IPv4] Already up to date (2 ranges, port 80,443/tcp)."* ]]
    [[ $output == *"[IPv6] Already up to date (1 ranges, port 80,443/tcp)."* ]]
    ! grep -qE '^ufw (allow|delete)' "$UFW_STUB_LOG"
}

@test "removes ranges Cloudflare no longer uses and keeps unrelated rules" {
    echo "ufw allow 22/tcp" > "$UFW_STUB_RULES"
    echo "ufw allow from 10.0.0.0/8 to any port 80,443 proto tcp" >> "$UFW_STUB_RULES"
    run_script
    printf '173.245.48.0/20\n198.51.100.0/24\n' > "$CURL_STUB_DIR/ips-v4"
    run_script
    [ "$status" -eq 0 ]
    [[ $output == *"+1 / -1"* ]]
    [[ $output == *"  + 198.51.100.0/24"* ]]
    [[ $output == *"  - 103.21.244.0/22 (port 80,443/tcp)"* ]]
    ! grep -q 103.21.244.0 "$UFW_STUB_RULES"
    grep -qxF "ufw allow 22/tcp" "$UFW_STUB_RULES"
    grep -qxF "ufw allow from 10.0.0.0/8 to any port 80,443 proto tcp" "$UFW_STUB_RULES"
}

@test "replaces the rules when the ports change, adding before deleting" {
    run_script
    : > "$UFW_STUB_LOG"
    run_script --ports 443
    [ "$status" -eq 0 ]
    [[ $output == *"+2 / -2"* ]]
    ! grep -q '80,443' "$UFW_STUB_RULES"
    # The guarantee holds per IP version, so look at the IPv4 rules only
    first_delete=$(grep -n '^ufw delete allow from 1' "$UFW_STUB_LOG" | head -1 | cut -d: -f1)
    last_allow=$(grep -n '^ufw allow from 1' "$UFW_STUB_LOG" | tail -1 | cut -d: -f1)
    [ "$last_allow" -lt "$first_delete" ]
}

@test "normalizes the order of the ports like ufw does" {
    run_script --ports 443,80
    : > "$UFW_STUB_LOG"
    run_script --ports 80,443
    [[ $output == *"Already up to date"* ]]
}

@test "--dry-run does not change anything" {
    run_script --dry-run
    [ "$status" -eq 0 ]
    [[ $output == *"+2 / -0"* ]]
    [[ $output == *"Dry run: no changes made."* ]]
    ! grep -qE '^ufw (allow|delete)' "$UFW_STUB_LOG"
}

@test "--ip-version 4 leaves IPv6 rules alone" {
    run_script
    echo '2606:4700::/32' > "$CURL_STUB_DIR/ips-v6"
    run_script --ip-version 4
    [ "$status" -eq 0 ]
    [[ $output != *"[IPv6]"* ]]
    grep -q 2400:cb00:: "$UFW_STUB_RULES"
}

@test "--remove deletes only the tagged rules" {
    echo "ufw allow 22/tcp" > "$UFW_STUB_RULES"
    run_script
    run_script --remove
    [ "$status" -eq 0 ]
    [[ $output == *"[IPv4] Removing 2 rules tagged 'cloudflare'."* ]]
    [ "$(rules)" = "ufw allow 22/tcp" ]
}

@test "--comment manages a separate set of rules" {
    run_script
    run_script --comment cf-spectrum --ports 25 --ip-version 4
    [ "$status" -eq 0 ]
    [ "$(grep -c "comment 'cf-spectrum'" "$UFW_STUB_RULES")" -eq 2 ]
    [ "$(grep -c "comment 'cloudflare'" "$UFW_STUB_RULES")" -eq 3 ]
}

@test "--source file reads local lists and ignores comments and blank lines" {
    printf '# Cloudflare\n\n192.0.2.0/24  # test\n' > v4.txt
    printf '2001:db8::/32\n' > v6.txt
    run_script --source file --ipv4-file v4.txt --ipv6-file v6.txt
    [ "$status" -eq 0 ]
    grep -q 'from 192.0.2.0/24 ' "$UFW_STUB_RULES"
    grep -q 'from 2001:db8::/32 ' "$UFW_STUB_RULES"
    ! grep -q 173.245.48.0 "$UFW_STUB_RULES"
}

@test "the lists in the repository are valid" {
    run_script --source file --ipv4-file "$ROOT/list_ipv4.txt" --ipv6-file "$ROOT/list_ipv6.txt" --dry-run
    [ "$status" -eq 0 ]
}

@test "an invalid list aborts without touching existing rules" {
    run_script
    echo '<html>Error</html>' > "$CURL_STUB_DIR/ips-v4"
    run_script
    [ "$status" -ne 0 ]
    [[ $output == *"invalid IPv4 CIDR"* ]]
    [ "$(rules | wc -l)" -eq 3 ]
}

@test "an empty list aborts without touching existing rules" {
    run_script
    : > "$CURL_STUB_DIR/ips-v4"
    run_script
    [ "$status" -ne 0 ]
    [[ $output == *"the IPv4 list is empty"* ]]
    [ "$(rules | wc -l)" -eq 3 ]
}

@test "a failed download aborts" {
    rm "$CURL_STUB_DIR/ips-v6"
    run_script
    [ "$status" -ne 0 ]
    [[ $output == *"could not read the IPv6 list"* ]]
}

@test "warns when the ports are also open to everyone" {
    echo "ufw allow 443/tcp" > "$UFW_STUB_RULES"
    echo "ufw allow 'Nginx Full'" >> "$UFW_STUB_RULES"
    run_script
    [ "$status" -eq 0 ]
    [[ $output == *"'ufw allow 443/tcp' allows port 443 from anywhere"* ]]
    [[ $output == *"allows a web server profile from anywhere"* ]]
}

@test "warns when ufw is inactive" {
    UFW_STUB_STATUS=inactive run_script
    [ "$status" -eq 0 ]
    [[ $output == *"ufw is inactive"* ]]
}

@test "rejects invalid options" {
    run_script --ports http
    [ "$status" -ne 0 ]
    run_script --proto icmp
    [ "$status" -ne 0 ]
    run_script --ip-version 5
    [ "$status" -ne 0 ]
    run_script --comment "it's"
    [ "$status" -ne 0 ]
    run_script --ports
    [[ $output == *"option --ports requires a value"* ]]
    run_script --bogus
    [[ $output == *"unknown option: --bogus"* ]]
}

@test "--help and --version" {
    run_script --help
    [ "$status" -eq 0 ]
    [[ $output == *"Usage: ufw-cloudflare"* ]]
    run_script --version
    [[ $output =~ ^ufw-cloudflare\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}
