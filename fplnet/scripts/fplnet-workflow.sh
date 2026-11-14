#!/usr/bin/env bash
# CI steps for the FPLNET routers in fplnet/hosts.json.
#   converge  verify each host by its Vault host certificate, re-sign it, assert the expiry
#   deploy    verify each host, restore its backbone key, deploy-rs it, then require its BGP sessions back
#   homepage  copy the lippok.dev build in HOMEPAGE_DIST to every edge as release HOMEPAGE_RELEASE and switch to it
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

# iBGP sessions of a host that are not Established.
ibgp_down() {
  ssh_host "$1" birdc show protocols | awk '$2 == "BGP" && $1 ~ /^ibgp_/ && !/Established/ { print $1 }'
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

# BGP session passwords from kv/fplnet/bgp/<host> become BIRD defines (vultr-password -> VULTR_PASSWORD)
# in /var/lib/bird/secrets.conf
restore_bgp_secrets() {
  local host="$1" response code
  response=$(curl -sS -w '\n%{http_code}' -H "X-Vault-Token: ${VAULT_TOKEN:?}" \
    "$VAULT_ADDR/v1/kv/data/fplnet/bgp/$host") || error "Could not reach Vault for the BGP secrets of $host."
  code="${response##*$'\n'}"
  [ "$code" = 404 ] && return 0
  [ "$code" = 200 ] || error "Vault returned HTTP $code for the BGP secrets of $host."

  # shellcheck disable=SC2016 # expands on the router
  jq -er '.data.data | to_entries[]
      | if (.value | test("^[A-Za-z0-9._-]+$")) then "define \(.key | ascii_upcase | gsub("-"; "_")) = \"\(.value)\";"
        else error("\(.key) has characters BIRD would need escaped") end' <<< "${response%$'\n'*}" \
    | ssh_host "$host" 'set -e
        f=/var/lib/bird/secrets.conf
        install -d -m 750 -g bird "${f%/*}"
        new=$(mktemp "$f.XXXXXX")
        cat > "$new"
        if cmp -s "$new" "$f" && systemctl is-active -q bird; then rm "$new"; exit 0; fi
        chgrp bird "$new"
        chmod 640 "$new"
        mv "$new" "$f"
        systemctl reload-or-restart bird' \
    || error "Could not restore the BGP secrets on $host."
}

# The edges get fplnet.net's cert by DNS-01
restore_cloudflare_token() {
  local host="$1"
  case "$host" in er1-*) ;; *) return 0 ;; esac
  curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN:?}" "$VAULT_ADDR/v1/kv/data/fplnet/cloudflare" \
    | jq -er '"CLOUDFLARE_DNS_API_TOKEN=\(.data.data["api-token"])"' \
    | ssh_host "$host" 'install -d -m 700 /etc/cloudflare && install -m 600 /dev/stdin /etc/cloudflare/credentials' \
    || error "Could not restore the Cloudflare token on $host."
}

# One ECH key for every edge (anycast), kv/fplnet/ech
restore_ech_key() {
  local host="$1"
  case "$host" in er1-*) ;; *) return 0 ;; esac
  # shellcheck disable=SC2016 # expands on the router
  curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN:?}" "$VAULT_ADDR/v1/kv/data/fplnet/ech" \
    | jq -er '.data.data.pem' \
    | ssh_host "$host" 'set -e
        f=/var/lib/fplnet-ech/fplnet.net.pem
        install -d -m 755 "${f%/*}"
        new=$(mktemp "$f.XXXXXX")
        cat > "$new"
        if cmp -s "$new" "$f"; then rm "$new"; exit 0; fi
        getent group nginx > /dev/null && chgrp nginx "$new"
        chmod 640 "$new"
        mv "$new" "$f"
        systemctl is-active -q nginx && systemctl reload nginx || true' \
    || error "Could not restore the ECH key on $host (is kv/fplnet/ech set?)."
}

restore_lippok_origin() {
  local host="$1" secret d=/var/lib/lippok-dev/tls
  case "$host" in er1-*) ;; *) return 0 ;; esac
  secret=$(curl -sSf -H "X-Vault-Token: ${VAULT_TOKEN:?}" "$VAULT_ADDR/v1/kv/data/fplnet/lippok-dev-origin") \
    || error "Could not read kv/fplnet/lippok-dev-origin for $host (is it set?)."
  jq -er '.data.data.cert' <<< "$secret" \
    | ssh_host "$host" "install -d -m 755 $d && cat > $d/origin.pem.new" \
    || error "Could not copy the lippok.dev origin certificate to $host."
  jq -er '.data.data.key' <<< "$secret" \
    | ssh_host "$host" "umask 077 && cat > $d/origin.key.new" \
    || error "Could not copy the lippok.dev origin key to $host."
  ssh_host "$host" "set -e
    cd $d
    grep -q 'BEGIN CERTIFICATE' origin.pem.new && grep -q 'PRIVATE KEY' origin.key.new
    if cmp -s origin.pem.new origin.pem && cmp -s origin.key.new origin.key; then rm origin.pem.new origin.key.new; exit 0; fi
    getent group nginx > /dev/null && chgrp nginx origin.key.new
    chmod 644 origin.pem.new
    chmod 640 origin.key.new
    mv origin.key.new origin.key
    mv origin.pem.new origin.pem
    systemctl is-active -q nginx && systemctl reload nginx || true" \
    || error "Could not install the lippok.dev origin certificate on $host."
}

site_up() {
  case "$1" in er1-*) ;; *) return 0 ;; esac
  ssh_host "$1" curl -fs -o /dev/null --max-time 5 --resolve 'fplnet.net:443:[2a0c:b641:f91::80]' https://fplnet.net/healthz
}

# Upstream and IX sessions are checked per host, so a broken one stops the rollout.
# iBGP waits for check_backbone: a change to both ends of a link (renumbering) keeps it
# down until the peer is deployed too.
deploy_host() {
  local host="$1" before
  before=$(established "$host" | grep -v '^ibgp_' || true)

  # Magic rollback reverts the host if deploy-rs cannot reconnect after activation.
  nix run "github:NixOS/nixpkgs/$(jq -er '.nodes.nixpkgs.locked.rev' "$FLAKE/flake.lock")#deploy-rs" -- \
    --skip-checks \
    --ssh-opts "${SSH_OPTS[*]}" \
    "$FLAKE#$host"

  # External sessions Established before the deploy must come back, and an edge must serve fplnet.net (no rollback, the build fails).
  for _ in $(seq 18); do
    if [ -z "$(comm -23 <(sort <<< "$before") <(established "$host" | sort))" ] && site_up "$host"; then
      echo "$host deployed; BGP sessions back: $(xargs <<< "$before")"
      return 0
    fi
    sleep 10
  done
  ssh_host "$host" birdc show protocols || true
  site_up "$host" || error "$host deployed, but fplnet.net does not answer on its anycast address."
  error "$host deployed, but these BGP sessions did not come back within 3 min: \
$(comm -23 <(sort <<< "$before") <(established "$host" | sort) | xargs)"
}

deploy_homepage() {
  local host="$1" dist="${HOMEPAGE_DIST:?}" release="${HOMEPAGE_RELEASE:?}"
  [ -f "$dist/index.html" ] || error "$dist has no index.html."
  [[ "$release" =~ ^[0-9a-f]{7,40}$ ]] || error "HOMEPAGE_RELEASE must be a commit hash."
  rsync -rlt --delete --chmod=D755,F644 -e "ssh ${SSH_OPTS[*]}" \
    "$dist/" "root@$(host_addr "$host"):/var/lib/lippok-dev/releases/$release/" \
    || error "Could not copy the site to $host."
  # shellcheck disable=SC2016 # expands on the router
  ssh_host "$host" "set -e
    cd /var/lib/lippok-dev
    ln -sfn releases/$release current.new
    mv -T current.new current
    ls -1t releases | grep -vx '$release' | tail -n +3 | sed 's|^|releases/|' | xargs -r rm -rf" \
    || error "Could not switch $host to release $release."
  ssh_host "$host" curl -fsk -o /dev/null --max-time 5 --resolve 'lippok.dev:443:[2a0c:b641:f91::80]' https://lippok.dev/ \
    || error "$host does not serve lippok.dev after the switch."
  echo "$host serves lippok.dev release $release."
}

# After every host is deployed, every iBGP session must be up.
check_backbone() {
  local down host
  for _ in $(seq 18); do
    down=""
    for host in $(hosts); do
      down+=$(ibgp_down "$host" | sed "s/^/$host:/" | xargs)" "
    done
    if [ -z "$(xargs <<< "$down")" ]; then
      echo "Backbone up: every iBGP session Established."
      return 0
    fi
    sleep 10
  done
  error "iBGP sessions still down 3 min after the rollout: $(xargs <<< "$down")"
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
      restore_bgp_secrets "$host"
      restore_cloudflare_token "$host"
      restore_ech_key "$host"
      restore_lippok_origin "$host"
      deploy_host "$host"
    done
    check_backbone
    ;;
  homepage)
    for host in $(hosts); do
      case "$host" in er1-*) ;; *) continue ;; esac
      verify_host "$host"
      deploy_homepage "$host"
    done
    ;;
  *) error "usage: $0 converge|deploy|homepage" ;;
esac
