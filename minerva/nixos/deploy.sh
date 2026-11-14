#!/usr/bin/env bash
# Deploy the NAS from your machine: ./deploy.sh            (switch to the new config)
#                                   ./deploy.sh --dry-activate  (only show what would change)
# The NAS builds its own system (remoteBuild), so this works from an ARM Mac. Root login there takes
# only the YubiKeys (files/admin-keys.pub): one PIN + touch, the connection is reused for the rest.
# If the new config breaks the login, deploy-rs rolls the NAS back on its own.
set -euo pipefail
cd "$(dirname "$0")"

# Apple's OpenSSH cannot use FIDO keys; Homebrew's can.
PATH="$(brew --prefix openssh)/bin:$PATH"
key=${NAS_SSH_KEY:-$HOME/.ssh/id_ed25519_sk_minerva}
mkdir -p ~/.ssh/cm

exec nix run nixpkgs#deploy-rs -- "path:$PWD#nas" --skip-checks \
  --ssh-opts "-i $key -o IdentitiesOnly=yes -o ControlMaster=auto -o ControlPath=$HOME/.ssh/cm/nas-%C -o ControlPersist=10m" \
  "$@"
