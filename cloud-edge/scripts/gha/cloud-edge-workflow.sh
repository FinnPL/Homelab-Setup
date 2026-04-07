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

  local state
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

  echo "nixos_state=unknown" >> "$GITHUB_OUTPUT"
  echo "nixos_installed=false" >> "$GITHUB_OUTPUT"
  echo "Could not verify NixOS marker via SSH (state unknown)."
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

usage() {
  cat << 'EOF'
Usage: cloud-edge-workflow.sh <command>
Commands:
  detect-instance-action
  prepare-edge-host
  setup-ssh
  detect-nixos-state
  write-ssh-keys-nix
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
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
