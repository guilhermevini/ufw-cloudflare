# ufw-cloudflare

[![CI](https://github.com/guilhermevini/ufw-cloudflare/actions/workflows/ci.yml/badge.svg)](https://github.com/guilhermevini/ufw-cloudflare/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash 4+](https://img.shields.io/badge/bash-4%2B-blue.svg)](ufw-cloudflare)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen.svg)](https://www.shellcheck.net)
[![Update Cloudflare IPs](https://github.com/guilhermevini/ufw-cloudflare/actions/workflows/update-ips.yml/badge.svg)](https://github.com/guilhermevini/ufw-cloudflare/actions/workflows/update-ips.yml)

Keep **[UFW](https://launchpad.net/ufw)** rules in sync with the public IP ranges of **[Cloudflare](https://www.cloudflare.com/ips/)**, so that only Cloudflare can reach your web server.

```
                ┌──────────────┐        ┌──────────────────────────────┐
  Internet ───▶ │  Cloudflare  │ ─────▶ │ UFW (allow Cloudflare IPs)   │ ───▶ nginx / Apache / Caddy
                └──────────────┘        └──────────────────────────────┘
   Attackers bypassing Cloudflare ─────────────────▶ ✖ blocked
```

## Why?

When a site is proxied by Cloudflare (orange cloud), visitors talk to Cloudflare, and Cloudflare talks to your server. But your server still has a public IP. **Anyone who finds it (old DNS records, certificate logs, mail headers, scanners) can go straight to the origin and skip Cloudflare's WAF, DDoS protection and rate limiting.**

The fix is to accept HTTP/HTTPS only from Cloudflare's IP addresses. Cloudflare publishes those lists, but they change over time. This project turns them into UFW rules and keeps them updated.

## Features

- Downloads the official lists from `https://www.cloudflare.com/ips-v4` and `/ips-v6`
- **Syncs**, not just adds: new ranges are allowed, ranges Cloudflare no longer uses are removed
- Only touches its own rules, tagged with a UFW comment (`cloudflare`); your SSH and other rules are left alone
- One rule per range for all ports (`80,443` by default), so ~22 rules instead of ~44
- Validates every CIDR and aborts on an empty or broken download, so a network hiccup never wipes your rules
- Prints a diff (`+` added / `-` removed) and supports `--dry-run`
- Adds new rules before deleting old ones, so changing ports never leaves Cloudflare blocked
- Warns when ports are still open to everyone (`ufw allow 443`, `ufw allow 'Nginx Full'`) or when UFW is inactive
- Idempotent and exits with a non-zero code on failure, so it is safe to run from cron or a systemd timer
- A single Bash script with no dependencies besides `ufw` and `curl` (or `wget`)
- Tested against the real UFW on Ubuntu 22.04 / 24.04 and Debian 12 / 13
- The IP lists in this repository ([`list_ipv4.txt`](list_ipv4.txt), [`list_ipv6.txt`](list_ipv6.txt)) are refreshed every week by a GitHub Action

## Installation

It is a single file. Download it from the [latest release](https://github.com/guilhermevini/ufw-cloudflare/releases/latest):

```bash
sudo curl -fsSL -o /usr/local/bin/ufw-cloudflare \
  https://github.com/guilhermevini/ufw-cloudflare/releases/latest/download/ufw-cloudflare
sudo chmod +x /usr/local/bin/ufw-cloudflare
```

To pin a version and verify its checksum (recommended for automation):

```bash
cd /tmp
curl -fsSLO https://github.com/guilhermevini/ufw-cloudflare/releases/download/v1.0.0/ufw-cloudflare
curl -fsSLO https://github.com/guilhermevini/ufw-cloudflare/releases/download/v1.0.0/ufw-cloudflare.sha256
sha256sum -c ufw-cloudflare.sha256 && sudo install -m 755 ufw-cloudflare /usr/local/bin/
```

Or clone the repository and run `./ufw-cloudflare` from it.

## Quick start

```bash
sudo ufw-cloudflare --dry-run   # preview
sudo ufw-cloudflare             # apply
```

Example output:

```
$ sudo ufw-cloudflare
[IPv4] 15 Cloudflare ranges, port 80,443/tcp: +15 / -0
  + 103.21.244.0/22
  + 103.22.200.0/22
  ...
[IPv4] Done.
[IPv6] 7 Cloudflare ranges, port 80,443/tcp: +7 / -0
  + 2400:cb00::/32
  ...
[IPv6] Done.

$ sudo ufw-cloudflare
[IPv4] Already up to date (15 ranges, port 80,443/tcp).
[IPv6] 7 Cloudflare ranges, port 80,443/tcp: +1 / -1
  + 2a06:98c0::/29
  - 2a06:98c0::/30 (port 80,443/tcp)
[IPv6] Done.
```

The rules show up in `ufw status` with their comment:

```
$ sudo ufw status
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
80,443/tcp                 ALLOW       103.21.244.0/22            # cloudflare
80,443/tcp                 ALLOW       103.22.200.0/22            # cloudflare
...
```

## Usage

```
ufw-cloudflare [--ports LIST] [--proto {tcp,udp}] [--ip-version {4,6,all}]
               [--source {url,file}] [--ipv4-file PATH] [--ipv6-file PATH]
               [--comment NAME] [--dry-run] [--remove]
```

| Option | Default | Description |
| --- | --- | --- |
| `--ports` | `80,443` | Ports to allow: `443`, `80,443`, `8000:8100`… |
| `--proto` | `tcp` | `tcp` or `udp` |
| `--ip-version` | `all` | Sync only IPv4 (`4`), only IPv6 (`6`) or both. IPv6 is skipped automatically when it is disabled in `/etc/default/ufw` |
| `--source` | `url` | `url` downloads the lists from Cloudflare; `file` reads local files |
| `--ipv4-file` / `--ipv6-file` | `list_ipv4.txt` / `list_ipv6.txt` | Files used with `--source file` (one CIDR per line, `#` comments allowed) |
| `--comment` | `cloudflare` | Comment that identifies the rules managed by the script |
| `--dry-run` | off | Show what would change without touching UFW |
| `--remove` | off | Delete every rule tagged with the comment (uninstall) |

Run it as root. Set `DEBUG=1` to trace the execution.

`--source file` is handy when the server cannot reach `cloudflare.com`: fetch the lists elsewhere (or use the ones in this repository) and pass them in.

Each `--comment` is an independent set of rules. For example, to also open a [Spectrum](https://developers.cloudflare.com/spectrum/) application on port 25 without affecting the HTTP rules:

```bash
sudo ufw-cloudflare --comment cloudflare-smtp --ports 25
```

## Use case: locking down an nginx origin behind Cloudflare

**Scenario:** `example.com` runs on an Ubuntu VPS with nginx. The DNS records are proxied by Cloudflare. You want the server to answer HTTP/HTTPS only to Cloudflare, while keeping SSH reachable.

### 1. Make sure SSH stays allowed, then enable UFW

```bash
sudo ufw allow OpenSSH     # or: sudo ufw allow 22/tcp
sudo ufw enable
```

### 2. Allow Cloudflare

```bash
sudo ufw-cloudflare
```

### 3. Remove the rules that open the web ports to everyone

This is the step people forget: UFW allows a packet as soon as **any** rule matches, so a leftover `allow 80/tcp` or `allow 'Nginx Full'` keeps the origin open to the whole internet. `ufw-cloudflare` warns about them; delete them:

```bash
sudo ufw status numbered
sudo ufw delete allow 'Nginx Full'   # or: sudo ufw delete allow 80/tcp, 443/tcp
```

### 4. Verify

```bash
curl -I https://example.com                                   # through Cloudflare → 200
curl -I --resolve example.com:443:203.0.113.10 https://example.com  # direct to the origin → times out
```

### 5. Keep the rules updated

Cloudflare adds ranges over time. A stale list **blocks legitimate traffic** coming from new Cloudflare data centers, so schedule the sync.

**systemd timer** (recommended): the units are in [`examples/systemd`](examples/systemd).

```bash
sudo curl -fsSL -o /etc/systemd/system/ufw-cloudflare.service \
  https://raw.githubusercontent.com/guilhermevini/ufw-cloudflare/main/examples/systemd/ufw-cloudflare.service
sudo curl -fsSL -o /etc/systemd/system/ufw-cloudflare.timer \
  https://raw.githubusercontent.com/guilhermevini/ufw-cloudflare/main/examples/systemd/ufw-cloudflare.timer
sudo systemctl daemon-reload
sudo systemctl enable --now ufw-cloudflare.timer

systemctl list-timers ufw-cloudflare.timer   # next run
journalctl -u ufw-cloudflare                 # logs
```

**cron**:

```cron
0 6 * * * /usr/local/bin/ufw-cloudflare >> /var/log/ufw-cloudflare.log 2>&1
```

### Good to know

- **Real visitor IPs:** with the origin behind Cloudflare, your logs show Cloudflare's addresses. Restore the visitor IP with nginx's [`real_ip` module](https://developers.cloudflare.com/support/troubleshooting/restoring-visitor-ips/restoring-original-visitor-ips/) (`set_real_ip_from` + `real_ip_header CF-Connecting-IP`), using the same lists.
- **Docker:** ports published with `docker run -p` are handled by Docker's own iptables rules and **bypass UFW**. Bind them to `127.0.0.1` and put a reverse proxy in front, or filter them in the `DOCKER-USER` chain.
- **Defense in depth:** an IP allowlist proves the request came from *a* Cloudflare data center, not from *your* zone. Combine it with [Authenticated Origin Pulls](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/), or avoid exposing the origin at all with [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

## Upgrading from `deploy.sh`

Earlier versions of this repository shipped `deploy.sh`, which added two untagged rules per range (ports 80 and 443) and never removed anything. `deploy.sh` still works (it now runs `ufw-cloudflare --source file`), but the old rules have no comment, so `ufw-cloudflare` does not manage them. To clean them up once, using the lists from that time:

```bash
git checkout e0cdeb7 -- list_ipv4.txt list_ipv6.txt
cat list_ipv4.txt list_ipv6.txt | while read -r ip; do
  for port in 80 443; do sudo ufw delete allow from "$ip" to any port "$port" proto tcp; done
done
git checkout HEAD -- list_ipv4.txt list_ipv6.txt
sudo ufw-cloudflare
```

## Updating the lists in this repository

The [`Update Cloudflare IPs`](.github/workflows/update-ips.yml) workflow runs every Monday and opens an auto-merged pull request when `list_ipv4.txt` / `list_ipv6.txt` change. To refresh them locally:

```bash
./update_ips.sh
```

You can also use these files as a source for other tools (nginx `set_real_ip_from`, iptables/nftables, cloud security groups, etc.), or sync from them with `ufw-cloudflare --source file`.

## Development

Tests use [bats](https://github.com/bats-core/bats-core). The unit tests replace `ufw` and `curl` with the stubs in [`tests/bin`](tests/bin), so they need no root. The integration test runs the script against the real UFW, so run it only in a throwaway container:

```bash
bats tests                                   # unit tests
shellcheck ufw-cloudflare update_ips.sh deploy.sh tests/integration.sh tests/bin/*

docker run --rm --cap-add NET_ADMIN -v "$PWD:/src" -w /src ubuntu:24.04 \
  bash -c 'apt-get update -qq && apt-get install -y -qq ufw >/dev/null && tests/integration.sh'
```

The [CI workflow](.github/workflows/ci.yml) runs ShellCheck, [actionlint](https://github.com/rhysd/actionlint), the unit tests and the integration test on Ubuntu 22.04 / 24.04 and Debian 12 / 13 on every push and pull request. Dependabot keeps the GitHub Actions up to date.

## Contributing

Issues and pull requests are welcome. Please make sure `bats tests` and `shellcheck` pass. Ideas for contributions:

- A `.deb` package or an Ansible role
- Equivalent scripts for `firewalld` and plain `nftables`
- Generating an nginx `real_ip` snippet from the same lists

## Releasing

1. Bump `VERSION` in [`ufw-cloudflare`](ufw-cloudflare), update the pinned version in this README, and merge to `main`.
2. Tag and push: `git tag v1.2.3 && git push origin v1.2.3`.

The [Release workflow](.github/workflows/release.yml) checks that the tag matches `VERSION`, runs the tests and creates a GitHub release with the script and its SHA-256 checksum attached, then downloads them back as documented above.

## Disclaimer

This is a community project and is not affiliated with, endorsed by, or supported by Cloudflare or Canonical. The IP lists are fetched from Cloudflare's public endpoints; always confirm the current ranges at [cloudflare.com/ips](https://www.cloudflare.com/ips/).

## License

[MIT](LICENSE) — free to use, modify and distribute, including for commercial purposes.
