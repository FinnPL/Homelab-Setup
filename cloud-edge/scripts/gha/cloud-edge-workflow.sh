#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_EDGE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
  local ip
  ip=$(get_instance_ip_value)

  echo "ip=$ip" >> "$GITHUB_OUTPUT"
  echo "Edge node IP: $ip"

  IP="$ip" setup_ssh
  IP="$ip" detect_nixos_state
}

setup_ssh() {
  require_var IP
  require_var OCI_SSH_PRIVATE_KEY

  local expected_fp="${EXPECTED_FP:-}"
  local attempts="${HOSTKEY_SCAN_ATTEMPTS:-10}"
  local delay_seconds="${HOSTKEY_SCAN_DELAY_SECONDS:-5}"
  local host_file="/tmp/edge_known_host"

  mkdir -p ~/.ssh
  printf '%s\n' "$OCI_SSH_PRIVATE_KEY" > ~/.ssh/edge_key
  chmod 600 ~/.ssh/edge_key

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

  if [ -n "$expected_fp" ]; then
    local actual_fp
    actual_fp=$(ssh-keygen -lf "$host_file" -E sha256 | awk 'NR==1 {print $2}')
    if [ "$actual_fp" != "$expected_fp" ]; then
      echo "Expected: $expected_fp"
      echo "Actual:   $actual_fp"
      error "SSH host key fingerprint mismatch."
    fi
  else
    warn "OCI_EDGE_SSH_HOSTKEY_SHA256 is not set; using TOFU host key trust."
  fi

  touch ~/.ssh/known_hosts
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

refresh_ssh_after_install() {
  require_var IP

  local attempts="${POST_INSTALL_SSH_ATTEMPTS:-30}"
  local delay_seconds="${POST_INSTALL_SSH_DELAY_SECONDS:-10}"
  local host_file="/tmp/edge_known_host"

  echo "Waiting for SSH to come back after NixOS install (host key will have changed)..."

  # Clear old known_hosts entries for this IP — NixOS generated new host keys
  ssh-keygen -R "$IP" -f ~/.ssh/known_hosts 2>/dev/null || true

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

wait_for_k3s() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local attempts="${K3S_WAIT_ATTEMPTS:-30}"
  local delay_seconds="${K3S_WAIT_DELAY_SECONDS:-10}"

  echo "Waiting for K3s API to become available..."

  local i
  for ((i = 1; i <= attempts; i++)); do
    if ssh "${ssh_opts[@]}" "root@$IP" 'kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes --no-headers 2>/dev/null' 2>/dev/null; then
      echo "K3s API is ready."
      return 0
    fi

    if [ "$i" -lt "$attempts" ]; then
      echo "K3s not ready yet (attempt $i/$attempts). Retrying in ${delay_seconds}s..."
      sleep "$delay_seconds"
    fi
  done

  error "K3s API did not become available after $attempts attempts"
}

fetch_kubeconfig() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
  )
  local output_path="${KUBECONFIG_OUTPUT:-$CLOUD_EDGE_DIR/k3s-services/kubeconfig.yaml}"

  echo "Fetching K3s kubeconfig from edge node..."

  mkdir -p "$(dirname "$output_path")"
  scp "${ssh_opts[@]}" "root@$IP:/etc/rancher/k3s/k3s.yaml" "$output_path"
  chmod 600 "$output_path"

  echo "kubeconfig_path=$output_path" >> "$GITHUB_OUTPUT"
  echo "K3s kubeconfig saved to $output_path"
}

setup_k3s_tunnel() {
  require_var IP

  local ssh_opts=(
    -i ~/.ssh/edge_key
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o UserKnownHostsFile=~/.ssh/known_hosts
    -o StrictHostKeyChecking=yes
    -o ExitOnForwardFailure=yes
  )

  echo "Establishing SSH tunnel to K3s API (localhost:6443 -> $IP:6443)..."

  # Forward local port 6443 to the edge node's K3s API.
  ssh "${ssh_opts[@]}" -fN -L 6443:127.0.0.1:6443 "root@$IP"

  echo "SSH tunnel established. K3s API accessible at https://127.0.0.1:6443"
}

usage() {
  cat << 'EOF'
Usage: cloud-edge-workflow.sh <command>
Commands:
  detect-instance-action
  terraform-apply-with-ad-fallback
  prepare-edge-host
  setup-ssh
  detect-nixos-state
  write-ssh-keys-nix
  refresh-ssh-after-install
  deploy-tailscale-credentials
  wait-for-tailscale
  wait-for-k3s
  fetch-kubeconfig
  setup-k3s-tunnel
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
    detect-nixos-state)
      detect_nixos_state
      ;;
    write-ssh-keys-nix)
      write_ssh_keys_nix
      ;;
    refresh-ssh-after-install)
      refresh_ssh_after_install
      ;;
    deploy-tailscale-credentials)
      deploy_tailscale_credentials
      ;;
    wait-for-tailscale)
      wait_for_tailscale
      ;;
    wait-for-k3s)
      wait_for_k3s
      ;;
    fetch-kubeconfig)
      fetch_kubeconfig
      ;;
    setup-k3s-tunnel)
      setup_k3s_tunnel
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
