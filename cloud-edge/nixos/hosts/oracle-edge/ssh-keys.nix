# SSH keys authorized for root on oracle-edge.
#
# IMPORTANT: CI (`write_ssh_keys_nix` in cloud-edge-workflow.sh) overwrites
# this file during deploy from the `OCI_SSH_PUBLIC_KEY` GitHub Actions var.
# The key hardcoded below MUST match that variable so CI rebuilds and local
# `nixos-rebuild` produce identical closures. If the CI var is rotated, update
# this file in the same commit — otherwise the next local rebuild wipes
# authorized_keys and locks SSH out.
#
# Historically this file was a placeholder (`keys = [ ];`), which meant any
# `nixos-rebuild switch` run outside CI silently deployed an empty
# authorized_keys and required serial-console recovery. Keeping the key
# committed here eliminates that footgun.
{
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRXt4rxMN1+gTiWXD8bsTYlbx02ocBmIrEFD7kJGOwW github-actions-oci-edge"
  ];
}
