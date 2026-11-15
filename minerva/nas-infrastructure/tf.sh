#!/usr/bin/env bash
# Plan or apply the NAS VM from the machine: ./tf.sh plan | ./tf.sh apply
# There is no stored Proxmox token: each run logs in to the host as root with a YubiKey (PIN + touch),
# mints a token of terraform-nas@pve that expires within the hour, and revokes it when Terraform exits.
set -euo pipefail
cd "$(dirname "$0")"

pve=${PVE_SSH:-root@$(jq -er .inventory.minerva.pve ../../inventory/minerva.json)}
# Apple's OpenSSH cannot use FIDO keys but Homebrew's can.
ssh_bin=${SSH_BIN:-$(brew --prefix openssh)/bin/ssh}
key=${NAS_SSH_KEY:-$HOME/.ssh/id_ed25519_sk_minerva}

want=$(sed -n '/terraform_version:/,/default:/s/.*default: *"\(.*\)"/\1/p' ../../.github/actions/tf-aws-setup/action.yaml)
have=$(terraform version -json | jq -r .terraform_version)
if [[ $have != "$want" ]]; then
  echo "terraform $want needed (the CI version, state written by a newer one breaks it), found $have" >&2
  exit 1
fi

mkdir -p ~/.ssh/cm
ctl=~/.ssh/cm/nas-tf-$$
pve_ssh() { "$ssh_bin" -i "$key" -o IdentitiesOnly=yes -o ControlMaster=auto -o ControlPath="$ctl" -o ControlPersist=2h "$pve" "$@"; }

id="run-$(date +%s)"
secret=$(pve_ssh "pveum user token add terraform-nas@pve $id --privsep 0 --expire $(($(date +%s) + 3600)) --comment tf.sh --output-format json" | jq -er .value)
cleanup() {
  pve_ssh "pveum user token remove terraform-nas@pve $id" || echo "could not revoke token $id, it expires within the hour" >&2
  "$ssh_bin" -o ControlPath="$ctl" -O exit "$pve" 2>/dev/null || true
}
trap cleanup EXIT
export TF_VAR_proxmox_api_token="terraform-nas@pve!$id=$secret"

eval "$(vault read -format=json aws/creds/tfstate | jq -r '.data | "export AWS_ACCESS_KEY_ID=\(.access_key) AWS_SECRET_ACCESS_KEY=\(.secret_key)" + (if .security_token then " AWS_SESSION_TOKEN=\(.security_token)" else "" end)')"

terraform init -input=false >/dev/null
terraform "$@"
