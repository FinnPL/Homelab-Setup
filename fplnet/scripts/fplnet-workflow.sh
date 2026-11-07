#!/usr/bin/env bash
# CI steps for the FPLNET routers in fplnet/hosts.json.
#   converge  verify each host by its Vault host certificate, re-sign it, assert the expiry
#   deploy    verify each host, restore its backbone key, deploy-rs it, then require its BGP sessions back
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
HOSTS_FILE="$ROOT/fplnet/hosts.json"
FLAKE="$ROOT/fplnet/nixos"
VAULT_ADDR="${VAULT_ADDR:-https://vault.cloud.lippok.dev}"
KNOWN_HOSTS="${RUNNER_TEMP:-/tmp}/fplnet_known_hosts"

error() {
  echo "::error::$*" >&2
  exit 1
}

hosts() { jq -r 'keys[]' "$HOSTS_FILE"; }
host_addr() { jq -er --arg h "$1" '.[$h].ssh' "$HOSTS_FILE"; }

SSH_OPTS=(
  -i "${SSH_KEY:?}"
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o ServerAliveInterval=15
  -o UserKnownHostsFile="$KNOWN_HOSTS"
  -o StrictHostKeyChecking=yes
)

ssh_host() {
  local host="$1"
  shift
  # shellcheck disable=SC2029 # callers build remote commands locally on purpose
  ssh "${SSH_OPTS[@]}" "root@$(host_addr "$host")" "$@"
}

trust_host_ca() {
  local ca h
  ca=$(cat "$ROOT/fplnet/vault_host_ca.pub")
  for h in $(hosts); do
    printf '@cert-authority %s %s\n' "$(host_addr "$h")" "$ca"
  done > "$KNOWN_HOSTS"
}

verify_host() {
  ssh_host "$1" true || error "$1 did not prove itself with a valid Vault host certificate (or is unreachable)."
  echo "$1 verified by its Vault host certificate."
}

sign_host_cert() {
  local host="$1" signed
  signed=$(ssh_host "$host" cat /etc/ssh/ssh_host_ed25519_key.pub \
    | jq -Rn --arg p "$(jq -er --arg h "$host" '.[$h].principals | join(",")' "$HOSTS_FILE")" \
      '{public_key: input, cert_type: "host", valid_principals: $p}' \
    | curl -sSf -X PUT -H "X-Vault-Token: ${VAULT_TOKEN:?}" --data-binary @- \
      "$VAULT_ADDR/v1/ssh-host-signer/sign/fplnet-host" \
    | jq -er '.data.signed_key') || error "Vault did not sign the host key of $host."

  ssh_host "$host" 'install -m 644 /dev/stdin /etc/ssh/ssh_host_ed25519_key-cert.pub && systemctl reload sshd && sleep 2' <<< "$signed"
  verify_host "$host"
}

# Judges the certificate on disk, not the sign call.
check_host_cert_expiry() {
  local host="$1" valid_to days
  valid_to=$(ssh_host "$host" cat /etc/ssh/ssh_host_ed25519_key-cert.pub \
    | ssh-keygen -L -f - | sed -n 's/.*Valid: from [^ ]* to \([^ ]*\).*/\1/p')
  [ -n "$valid_to" ] || error "No readable host certificate on $host."

  days=$((($(date -u -d "${valid_to/T/ }" +%s) - $(date -u +%s)) / 86400))
  echo "Host certificate on $host expires $valid_to ($days days left)."
  [ "$days" -ge 14 ] || error "Host certificate on $host has $days days left and renewal is not taking."
}

established() {
  ssh_host "$1" birdc show protocols | awk '$2 == "BGP" && /Established/ { print $1 }'
}

# Vault holds the backbone WireGuard key, so a reinstalled router comes back with the same public key.
restore_wg_key() {
  local host="$1"
  # shellcheck disable=SC2016 # expands on the router
  curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN:?}" "$VAULT_ADDR/v1/kv/data/fplnet/wireguard/$host" \
    | jq -er '.data.data["private-key"]' \
    | ssh_host "$host" 'set -e
        key=/var/lib/wireguard/backbone.key
        install -d -m 750 -g systemd-network "${key%/*}"
        new=$(mktemp "$key.XXXXXX")
        cat > "$new"
        if cmp -s "$new" "$key"; then rm "$new"; exit 0; fi
        chgrp systemd-network "$new"
        chmod 640 "$new"
        mv "$new" "$key"
        for link in /sys/class/net/wg-er1-* /sys/class/net/wg-gw1-*; do
          [ -e "$link" ] && ip link delete "${link##*/}"
        done
        networkctl reload' \
    || error "Could not restore the backbone WireGuard key on $host."
}

deploy_host() {
  local host="$1" before
  before=$(established "$host")

  # Magic rollback reverts the host if deploy-rs cannot reconnect after activation.
  nix run "github:NixOS/nixpkgs/$(jq -er '.nodes.nixpkgs.locked.rev' "$FLAKE/flake.lock")#deploy-rs" -- \
    --skip-checks \
    --ssh-opts "${SSH_OPTS[*]}" \
    "$FLAKE#$host"

  # Sessions Established before the deploy must come back (no rollback, the build fails).
  for _ in $(seq 18); do
    if [ -z "$(comm -23 <(sort <<< "$before") <(established "$host" | sort))" ]; then
      echo "$host deployed; BGP sessions back: $(xargs <<< "$before")"
      return 0
    fi
    sleep 10
  done
  ssh_host "$host" birdc show protocols || true
  error "$host deployed, but these BGP sessions did not come back within 3 min: \
$(comm -23 <(sort <<< "$before") <(established "$host" | sort) | xargs)"
}

trust_host_ca
case "${1:-}" in
  converge)
    for host in $(hosts); do
      verify_host "$host"
      sign_host_cert "$host"
      check_host_cert_expiry "$host"
    done
    ;;
  deploy)
    for host in $(hosts); do
      verify_host "$host"
      restore_wg_key "$host"
      deploy_host "$host"
    done
    ;;
  *) error "usage: $0 converge|deploy" ;;
esac
