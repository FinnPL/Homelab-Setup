#!/usr/bin/env bash
set -euo pipefail

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

get_instance_ip_value() {
  terraform init -input=false -lock=false > /dev/null

  local ip
  ip=$(terraform output -raw instance_public_ip)
  if [ -z "$ip" ]; then
    error "Could not read instance_public_ip from Terraform outputs"
  fi

  printf '%s\n' "$ip"
}

get_availability_domains() {
  local plan_ads
  plan_ads=$(terraform show -json .planfile 2>/dev/null | jq -r '
    .. | objects
    | select(.address? == "data.oci_identity_availability_domains.ads")
    | .values.availability_domains[]?.name
  ' 2>/dev/null || true)

  if [ -n "$plan_ads" ]; then
    printf '%s\n' "$plan_ads"
    return 0
  fi

  warn "Could not read availability domains from .planfile. Querying provider directly."

  terraform init -input=false -lock=false > /dev/null

  local ads_json
  ads_json=$(terraform console -no-color << 'EOF' | tail -n 1
jsonencode(data.oci_identity_availability_domains.ads.availability_domains[*].name)
EOF
)

  if [ -z "$ads_json" ]; then
    error "Could not determine OCI availability domains for apply fallback"
  fi

  printf '%s\n' "$ads_json" | jq -r 'fromjson[]'
}

terraform_apply_with_ad_fallback() {
  local configured_ad
  configured_ad="$(printf '%s' "${TF_VAR_instance_availability_domain:-}" | tr -d '\r' | xargs)"

  local -a replace_args=()
  if [ -n "${REPLACE_TARGET:-}" ]; then
    echo "AD-fallback apply will use -replace=${REPLACE_TARGET}"
    replace_args+=(-replace="${REPLACE_TARGET}")
  fi

  local -a ad_candidates=()
  if [ -n "$configured_ad" ]; then
    ad_candidates+=("$configured_ad")
  fi

  local ad
  local existing
  local duplicate
  while IFS= read -r ad; do
    [ -z "$ad" ] && continue

    duplicate="false"
    for existing in "${ad_candidates[@]}"; do
      if [ "$existing" = "$ad" ]; then
        duplicate="true"
        break
      fi
    done

    if [ "$duplicate" = "false" ]; then
      ad_candidates+=("$ad")
    fi
  done < <(get_availability_domains)

  if [ "${#ad_candidates[@]}" -eq 0 ]; then
    error "No OCI availability domains found for fallback apply"
  fi

  local attempt=0
  local total="${#ad_candidates[@]}"
  local log_file
  local apply_exit

  for ad in "${ad_candidates[@]}"; do
    attempt=$((attempt + 1))
    log_file="$(mktemp)"

    echo "Terraform apply attempt ${attempt}/${total} in availability domain: $ad"

    set +e
    terraform apply -lock-timeout=10m -auto-approve -input=false -var "instance_availability_domain=$ad" "${replace_args[@]}" 2>&1 | tee "$log_file"
    apply_exit=${PIPESTATUS[0]}
    set -e

    if [ "$apply_exit" -eq 0 ]; then
      echo "Terraform apply succeeded in availability domain: $ad"
      rm -f "$log_file"
      return 0
    fi

    if grep -qi "Out of host capacity" "$log_file"; then
      warn "OCI reported host capacity shortage in $ad. Trying next availability domain."
      rm -f "$log_file"
      continue
    fi

    echo "Terraform apply failed in availability domain: $ad"
    cat "$log_file"
    rm -f "$log_file"
    error "Terraform apply failed with a non-capacity error; stopping fallback attempts"
  done

  error "Terraform apply failed in all candidate availability domains due to host capacity shortage"
}

detect_instance_action() {
  local action
  action=$(terraform show -json .planfile | jq -r '
    first(
      .resource_changes[]?
      | select(.address == "oci_core_instance.edge")
      | .change.actions
    ) // ["no-op"]
    | if (index("create") and index("delete")) then "replace"
      elif index("create") then "create"
      elif index("update") then "update"
      elif index("delete") then "delete"
      else "nochange"
      end
  ')

  local is_new="false"
  if [ "$action" = "create" ] || [ "$action" = "replace" ]; then
    is_new="true"
  fi

  echo "instance_action=$action" >> "$GITHUB_OUTPUT"
  echo "instance_new=$is_new" >> "$GITHUB_OUTPUT"

  echo "Edge instance plan action: $action"
  echo "Fresh VM proof from plan: $is_new"
}

prepare_edge_host() {
  local ip private_ip
  ip=$(get_instance_ip_value)

  private_ip=$(terraform output -raw instance_private_ip 2>/dev/null || echo "")

  echo "ip=$ip" >> "$GITHUB_OUTPUT"
  echo "private_ip=$private_ip" >> "$GITHUB_OUTPUT"
  echo "Edge node public IP: $ip, private IP: $private_ip"

  IP="$ip" setup_ssh
  IP="$ip" detect_nixos_state

  # a run may issue that host a certificate, exactly when it is a fresh VM or a deliberate dispatch.
  if [ "${ALLOW_HOST_TOFU:-false}" = "true" ]; then
    IP="$ip" sign_host_cert
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

detect_nixos_state() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local attempts="${NIXOS_STATE_CHECK_ATTEMPTS:-8}"
  local delay_seconds="${NIXOS_STATE_CHECK_DELAY_SECONDS:-5}"

  local state
  local i
  for ((i = 1; i <= attempts; i++)); do
    if state=$(ssh "${ssh_opts[@]}" "root@$IP" 'if test -x /run/current-system/sw/bin/nixos-version; then echo installed; else echo absent; fi' 2>/dev/null); then
      if [ "$state" = "installed" ]; then
        echo "nixos_state=installed" >> "$GITHUB_OUTPUT"
        echo "nixos_installed=true" >> "$GITHUB_OUTPUT"
        echo "Detected existing NixOS installation."
        return 0
      fi

      echo "nixos_state=absent" >> "$GITHUB_OUTPUT"
      echo "nixos_installed=false" >> "$GITHUB_OUTPUT"
      echo "No NixOS marker detected."
      return 0
    fi

    if [ "$i" -lt "$attempts" ]; then
      echo "Could not verify NixOS marker yet (attempt $i/$attempts). Retrying in ${delay_seconds}s..."
      sleep "$delay_seconds"
    fi
  done

  echo "nixos_state=unknown" >> "$GITHUB_OUTPUT"
  echo "nixos_installed=false" >> "$GITHUB_OUTPUT"
  echo "Could not verify NixOS marker via SSH after $attempts attempts (state unknown)."
}

write_ssh_keys_nix() {
  require_var OCI_SSH_PUBLIC_KEY

  cat > "$CLOUD_EDGE_DIR/nixos/hosts/oracle-edge/ssh-keys.nix" << EOF
{
  users.users.root.openssh.authorizedKeys.keys = [
    "$OCI_SSH_PUBLIC_KEY"
  ];
}
EOF
}

write_acme_email_nix() {
  require_var ACME_EMAIL

  cat > "$CLOUD_EDGE_DIR/nixos/hosts/oracle-edge/acme-email.nix" << EOF
{
  security.acme.defaults.email = "$ACME_EMAIL";
}
EOF
}

refresh_ssh_after_install() {
  require_var IP

  local attempts="${POST_INSTALL_SSH_ATTEMPTS:-30}"
  local delay_seconds="${POST_INSTALL_SSH_DELAY_SECONDS:-10}"
  local host_file="/tmp/edge_known_host"

  echo "Waiting for SSH to come back after NixOS install (host key will have changed)..."

  require_ssh_cert

  # Clear old known_hosts entries for this IP — NixOS generated new host keys.
  # -R leaves @cert-authority lines alone, so CA trust survives.
  ssh-keygen -R "$IP" -f ~/.ssh/known_hosts 2>/dev/null || true
  trust_host_ca

  : > "$host_file"
  local i
  for ((i = 1; i <= attempts; i++)); do
    if ssh-keyscan -T 5 -t ed25519 -H "$IP" > "$host_file" 2>/dev/null && [ -s "$host_file" ]; then
      echo "SSH is back up (attempt $i/$attempts)."
      break
    fi

    if [ "$i" -lt "$attempts" ]; then
      echo "SSH not available yet (attempt $i/$attempts). Retrying in ${delay_seconds}s..."
      sleep "$delay_seconds"
    fi
  done

  if [ ! -s "$host_file" ]; then
    error "SSH did not come back on $IP after $attempts attempts"
  fi

  local new_fp
  new_fp=$(ssh-keygen -lf "$host_file" -E sha256 | awk 'NR==1 {print $2}')
  echo "New NixOS host key fingerprint: $new_fp"

  cat "$host_file" >> ~/.ssh/known_hosts
  echo "Known hosts updated with new NixOS host key."

  # The install replaced the host key, so the old certificate no longer matches.
  sign_host_cert
}

reboot_edge() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local attempts="${REBOOT_SSH_ATTEMPTS:-40}"
  local delay_seconds="${REBOOT_SSH_DELAY_SECONDS:-10}"

  # `nixos-rebuild boot` already moved the system profile to the staged
  # generation; that is what the host must be running once it comes back.
  local expected
  expected=$(ssh "${ssh_opts[@]}" "root@$IP" 'readlink -f /nix/var/nix/profiles/system') ||
    error "Could not read the staged system generation on $IP"

  echo "Rebooting $IP into $expected ..."

  # Detached so sshd going down does not race the exit status of the command.
  ssh "${ssh_opts[@]}" "root@$IP" 'systemd-run --on-active=2 --collect systemctl reboot' ||
    error "Could not schedule reboot on $IP"

  # Let the host actually go down, or the first probe answers from the old sshd.
  sleep 15

  local i booted=""
  for ((i = 1; i <= attempts; i++)); do
    if booted=$(ssh "${ssh_opts[@]}" "root@$IP" 'readlink -f /run/current-system' 2>/dev/null) && [ -n "$booted" ]; then
      echo "Host is back (attempt $i/$attempts)."
      break
    fi

    booted=""
    echo "Host not back yet (attempt $i/$attempts)"
    if [ "$i" -lt "$attempts" ]; then
      sleep "$delay_seconds"
    fi
  done

  if [ -z "$booted" ]; then
    error "$IP did not come back after reboot ($attempts attempts)"
  fi

  # A silent fallback to the previous generation must not read as success.
  if [ "$booted" != "$expected" ]; then
    error "Booted the wrong generation on $IP. staged=$expected running=$booted"
  fi

  echo "Rebooted into $booted"
}

deploy_wireguard_keys() {
  require_var IP
  require_var WG_PRIVATE_KEY
  require_var WG_PEER_PUBKEY

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  echo "Deploying WireGuard keys to edge node..."
  ssh "${ssh_opts[@]}" "root@$IP" '
    mkdir -p /etc/wireguard
    cat > /etc/wireguard/private.key
    chmod 600 /etc/wireguard/private.key
  ' <<< "$WG_PRIVATE_KEY"

  ssh "${ssh_opts[@]}" "root@$IP" '
    mkdir -p /etc/wireguard
    cat > /etc/wireguard/peer-pubkey
    chmod 644 /etc/wireguard/peer-pubkey
  ' <<< "$WG_PEER_PUBKEY"

  ssh "${ssh_opts[@]}" "root@$IP" 'systemctl restart homelab-wg || true'

  echo "WireGuard keys deployed and service triggered."
}

wait_for_wireguard() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local attempts=15
  local delay_seconds=5

  echo "Waiting for WireGuard tunnel to come up..."

  local i
  for ((i = 1; i <= attempts; i++)); do
    if ssh "${ssh_opts[@]}" "root@$IP" 'ip link show wg0 2>/dev/null' >/dev/null 2>&1; then
      echo "WireGuard tunnel is up."
      return 0
    fi

    echo "WireGuard not ready yet (attempt $i/$attempts)"
    if [ "$i" -lt "$attempts" ]; then
      sleep "$delay_seconds"
    fi
  done

  error "WireGuard tunnel did not come up after $attempts attempts"
}

deploy_myip_secrets() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )

  echo "Deploying MyIP API key env file..."
  # Local (client-side) expansion is intended: these secrets live in the runner env
  # and must be interpolated here, then streamed to the remote `cat`. Quoting EOF would
  # ship literal ${VAR} text to a host that has no such vars.
  # shellcheck disable=SC2087
  ssh "${ssh_opts[@]}" "root@$IP" '
    install -d -m 0700 /etc/myip
    umask 077
    cat > /etc/myip/secrets.env
    chmod 600 /etc/myip/secrets.env
  ' <<EOF
CLOUDFLARE_API=${MYIP_CLOUDFLARE_API:-}
MAXMIND_ACCOUNT_ID=${MAXMIND_ACCOUNT_ID:-}
MAXMIND_LICENSE_KEY=${MAXMIND_LICENSE_KEY:-}
MAXMIND_AUTO_UPDATE=${MAXMIND_AUTO_UPDATE:-false}
EOF

  ssh "${ssh_opts[@]}" "root@$IP" 'systemctl restart podman-myip.service || true'
  echo "MyIP secrets deployed and container restarted."
}

deploy_cloudflare_credentials() {
  require_var IP
  require_var CLOUDFLARE_API_TOKEN

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )

  echo "Deploying Cloudflare credentials for ACME DNS-01..."
  # Local expansion is intended (see deploy_myip_secrets): $CLOUDFLARE_API_TOKEN is a
  # runner env secret interpolated here, then streamed to the remote `cat`.
  # shellcheck disable=SC2087
  ssh "${ssh_opts[@]}" "root@$IP" '
    install -d -m 0700 /etc/cloudflare
    umask 077
    cat > /etc/cloudflare/credentials
    chmod 600 /etc/cloudflare/credentials
  ' <<EOF
CLOUDFLARE_DNS_API_TOKEN=$CLOUDFLARE_API_TOKEN
EOF

  # Kick acme to issue/renew now that credentials exist. The unit is a oneshot
  # backed by a daily timer; starting it manually is safe and idempotent.
  ssh "${ssh_opts[@]}" "root@$IP" '
    systemctl start acme-cloud.lippok.dev.service || true
  '

  echo "Cloudflare credentials deployed and acme issuance triggered."
}

deploy_tailscale_credentials() {
  require_var IP
  require_var TAILSCALE_OAUTH_SECRET

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  echo "Deploying Tailscale OAuth credentials to edge node..."
  ssh "${ssh_opts[@]}" "root@$IP" '
    mkdir -p /etc/tailscale
    cat > /etc/tailscale/authkey
    chmod 600 /etc/tailscale/authkey
  ' <<< "$TAILSCALE_OAUTH_SECRET"

  # Deploy the subnet CIDR for Tailscale route advertisement
  local subnet_cidr
  subnet_cidr=$(cd "$CLOUD_EDGE_DIR" && terraform output -raw public_subnet_cidr)
  echo "Deploying Tailscale subnet CIDR ($subnet_cidr) to edge node..."
  ssh "${ssh_opts[@]}" "root@$IP" '
    mkdir -p /etc/tailscale
    cat > /etc/tailscale/subnet-cidr
    chmod 644 /etc/tailscale/subnet-cidr
  ' <<< "$subnet_cidr"

  # Restarting to pick up the authkey file.
  ssh "${ssh_opts[@]}" "root@$IP" 'systemctl restart tailscaled-autoconnect.service'

  echo "Tailscale credentials and subnet CIDR deployed."
}

wait_for_tailscale() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local attempts="${TAILSCALE_WAIT_ATTEMPTS:-30}"
  local delay_seconds="${TAILSCALE_WAIT_DELAY_SECONDS:-10}"

  echo "Waiting for Tailscale to connect..."

  local i
  for ((i = 1; i <= attempts; i++)); do
    local ts_status
    if ts_status=$(ssh "${ssh_opts[@]}" "root@$IP" 'tailscale status --json 2>/dev/null' 2>/dev/null); then
      local backend_state
      backend_state=$(printf '%s' "$ts_status" | jq -r '.BackendState // empty')

      if [ "$backend_state" = "Running" ]; then
        local ts_ip
        ts_ip=$(printf '%s' "$ts_status" | jq -r '.TailscaleIPs[0] // empty')

        echo "tailscale_ip=$ts_ip" >> "$GITHUB_OUTPUT"
        echo "Tailscale connected. Tailscale IP: $ts_ip"
        return 0
      fi

      echo "Tailscale state: $backend_state (attempt $i/$attempts)"
    else
      echo "Could not query Tailscale status (attempt $i/$attempts)"
    fi

    if [ "$i" -lt "$attempts" ]; then
      sleep "$delay_seconds"
    fi
  done

  error "Tailscale did not connect after $attempts attempts"
}

usage() {
  cat << 'EOF'
Usage: cloud-edge-workflow.sh <command>
Commands:
  detect-instance-action
  terraform-apply-with-ad-fallback
  prepare-edge-host
  setup-ssh
  sign-host-cert
  check-host-cert-expiry
  detect-nixos-state
  write-ssh-keys-nix
  write-acme-email-nix
  refresh-ssh-after-install
  reboot-edge
  deploy-cloudflare-credentials
  deploy-myip-secrets
  deploy-tailscale-credentials
  deploy-wireguard-keys
  wait-for-tailscale
  wait-for-wireguard
EOF
}

main() {
  if [ "$#" -ne 1 ]; then
    usage
    exit 1
  fi

  case "$1" in
    detect-instance-action)
      detect_instance_action
      ;;
    terraform-apply-with-ad-fallback)
      terraform_apply_with_ad_fallback
      ;;
    prepare-edge-host)
      prepare_edge_host
      ;;
    setup-ssh)
      setup_ssh
      ;;
    sign-host-cert)
      sign_host_cert
      ;;
    check-host-cert-expiry)
      check_host_cert_expiry
      ;;
    detect-nixos-state)
      detect_nixos_state
      ;;
    write-ssh-keys-nix)
      write_ssh_keys_nix
      ;;
    write-acme-email-nix)
      write_acme_email_nix
      ;;
    refresh-ssh-after-install)
      refresh_ssh_after_install
      ;;
    reboot-edge)
      reboot_edge
      ;;
    deploy-cloudflare-credentials)
      deploy_cloudflare_credentials
      ;;
    deploy-myip-secrets)
      deploy_myip_secrets
      ;;
    deploy-tailscale-credentials)
      deploy_tailscale_credentials
      ;;
    deploy-wireguard-keys)
      deploy_wireguard_keys
      ;;
    wait-for-tailscale)
      wait_for_tailscale
      ;;
    wait-for-wireguard)
      wait_for_wireguard
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
