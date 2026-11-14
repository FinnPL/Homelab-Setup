#!/usr/bin/env bash
# Weekly host-certificate renewal for the OCI VM oracle-edge (ssh-cert-converge.yaml). The VM itself
# is no longer managed in this repo; it keeps SSH and Tailscale only.
#   setup-ssh               verify the host by its Vault host certificate (or adopt it with ALLOW_HOST_TOFU)
#   sign-host-cert          have Vault re-sign the host key
#   check-host-cert-expiry  fail if the certificate on disk has under HOST_CERT_MIN_DAYS left
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}"
# One Vault host CA for every site.
HOST_CA_FILE="$ROOT/fplnet/vault_host_ca.pub"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_EDGE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOST_CA_FILE="$CLOUD_EDGE_DIR/vault_host_ca.pub"

error() {
  echo "::error::$*"
  exit 1
}

warn() {
  echo "::warning::$*"
}

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    error "Missing required environment variable: $name"
  fi
}

require_ssh_cert() {
  if [ ! -s ~/.ssh/edge_key ] || [ ! -s ~/.ssh/edge_key-cert.pub ]; then
    error "No signed key at ~/.ssh/edge_key. Run the vault-ssh-cert action \
(role: oci-edge, key-path: ~/.ssh/edge_key) before this step."
  fi

  if ! ssh-keygen -Lf ~/.ssh/edge_key-cert.pub | grep -E 'Key ID|Valid:|^ *root$'; then
    error "The file at ~/.ssh/edge_key-cert.pub is not a readable certificate."
  fi
}

# Pins the host CA to this one address.
trust_host_ca() {
  require_var IP

  mkdir -p ~/.ssh
  touch ~/.ssh/known_hosts

  local ca_line
  ca_line="@cert-authority $IP $(cat "$HOST_CA_FILE")"

  if ! grep -qxF "$ca_line" ~/.ssh/known_hosts; then
    printf '%s\n' "$ca_line" >> ~/.ssh/known_hosts
  fi
}

# Succeeds only when the host proves itself with a Vault-signed certificate.
host_cert_verifies() {
  require_var IP

  local ca_only="/tmp/edge_cert_only_known_hosts"
  printf '@cert-authority %s %s\n' "$IP" "$(cat "$HOST_CA_FILE")" > "$ca_only"

  ssh -i ~/.ssh/edge_key \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o IdentitiesOnly=yes \
    -o UserKnownHostsFile="$ca_only" \
    -o StrictHostKeyChecking=yes \
    "root@$IP" true > /dev/null 2>&1
}

# Has Vault certify the host's own key, so later runs verify by certificate instead of TOFU.
sign_host_cert() {
  require_var IP
  require_var VAULT_TOKEN

  local vault_addr="${VAULT_ADDR:-https://vault.cloud.lippok.dev}"
  local role="${VAULT_SSH_HOST_ROLE:-oci-edge-host}"

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )

  local host_pubkey
  if ! host_pubkey=$(ssh "${ssh_opts[@]}" "root@$IP" 'cat /etc/ssh/ssh_host_ed25519_key.pub'); then
    warn "Could not read the host key from $IP; leaving its host certificate unchanged."
    return 0
  fi

  local signed
  if ! signed=$(jq -n --arg pk "$host_pubkey" --arg p "$IP,oracle-edge" \
        '{public_key: $pk, cert_type: "host", valid_principals: $p}' \
      | curl -sS -f -X PUT \
          -H "X-Vault-Token: $VAULT_TOKEN" \
          --data-binary @- \
          "${vault_addr}/v1/ssh-host-signer/sign/${role}" \
      | jq -r '.data.signed_key'); then
    warn "Vault did not sign the host key for role $role; leaving current trust in place."
    return 0
  fi

  if [ -z "$signed" ] || [ "$signed" = "null" ]; then
    warn "Vault returned no host certificate for role $role; leaving current trust in place."
    return 0
  fi

  # KillMode=process and Type=notify-reload mean this cannot drop the session
  # we are issuing it over.
  ssh "${ssh_opts[@]}" "root@$IP" '
    cat > /etc/ssh/ssh_host_ed25519_key-cert.pub
    chmod 644 /etc/ssh/ssh_host_ed25519_key-cert.pub
    systemctl reload sshd 2>/dev/null || systemctl reload ssh
  ' <<< "$signed"

  if host_cert_verifies; then
    echo "Host certificate installed; $IP now verifies against the Vault host CA."
  else
    warn "Installed a host certificate but $IP still does not verify against the host CA."
  fi
}

# sign_host_cert only warns when Vault or the host is unreachable would let the scheduled renewal go green having renewed nothing.
check_host_cert_expiry() {
  require_var IP

  local min_days="${HOST_CERT_MIN_DAYS:-14}"
  local cert_file="/tmp/edge_host_cert.pub"

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )

  if ! ssh "${ssh_opts[@]}" "root@$IP" 'cat /etc/ssh/ssh_host_ed25519_key-cert.pub' > "$cert_file"; then
    error "Could not read the host certificate from $IP"
  fi

  local valid_to
  valid_to=$(ssh-keygen -L -f "$cert_file" | sed -n 's/.*Valid: from [^ ]* to \([^ ]*\).*/\1/p')
  if [ -z "$valid_to" ]; then
    error "No validity window in the host certificate on $IP"
  fi

  local valid_to_epoch
  if ! valid_to_epoch=$(date -u -d "${valid_to/T/ }" +%s 2>/dev/null); then
    valid_to_epoch=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$valid_to" +%s)
  fi

  local days
  days=$(((valid_to_epoch - $(date -u +%s)) / 86400))
  echo "Host certificate on $IP expires $valid_to (${days} days left)."

  if [ "$days" -lt "$min_days" ]; then
    error "Host certificate on $IP has ${days} days left and renewal is not taking. \
Fix it before it expires — afterwards setup_ssh fails closed and recovery needs a \
workflow_dispatch with allow_host_tofu=true."
  fi
}

setup_ssh() {
  require_var IP

  local attempts="${HOSTKEY_SCAN_ATTEMPTS:-10}"
  local delay_seconds="${HOSTKEY_SCAN_DELAY_SECONDS:-5}"
  local host_file="/tmp/edge_known_host"

  require_ssh_cert
  trust_host_ca

  if host_cert_verifies; then
    echo "Host $IP verified by its Vault host certificate."
    return 0
  fi

  if [ "${ALLOW_HOST_TOFU:-false}" != "true" ]; then
    error "$IP presented no valid Vault host certificate and this is not a fresh VM. \
Re-run with workflow_dispatch allow_host_tofu=true to adopt the current host key."
  fi

  : > "$host_file"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if ssh-keyscan -T 5 -t ed25519 -H "$IP" > "$host_file" 2>/dev/null && [ -s "$host_file" ]; then
      break
    fi

    if [ "$i" -lt "$attempts" ]; then
      echo "Host key not available yet (attempt $i/$attempts). Retrying in ${delay_seconds}s..."
      sleep "$delay_seconds"
    fi
  done

  if [ ! -s "$host_file" ]; then
    error "Could not fetch SSH host key from $IP after $attempts attempts"
  fi

  warn "Adopting $IP on trust-on-first-use; it will be certified before this run ends."
  cat "$host_file" >> ~/.ssh/known_hosts
}

case "${1:-}" in
  setup-ssh) setup_ssh ;;
  sign-host-cert) sign_host_cert ;;
  check-host-cert-expiry) check_host_cert_expiry ;;
  *) error "usage: $0 setup-ssh|sign-host-cert|check-host-cert-expiry" ;;
esac
