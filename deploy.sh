#!/usr/bin/env bash

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace       # Trace the execution of the script (debug)
fi

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline

# Main control flow
function main() {
    list_ipv4="list_ipv4.txt"
    list_ipv6="list_ipv6.txt"

    while IFS= read -r ip
    do
        ufw allow from $ip proto tcp to any port 80
        ufw allow from $ip proto tcp to any port 443
    done < "$list_ipv4"

    while IFS= read -r ip
    do
        ufw allow from $ip proto tcp to any port 80
        ufw allow from $ip proto tcp to any port 443
    done < "$list_ipv6"
}

# Template, assemble!
main
