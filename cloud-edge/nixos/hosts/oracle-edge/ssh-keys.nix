# Placeholder module kept in git so flake source always includes this file.
# CI overwrites it during deploy with OCI_SSH_PUBLIC_KEY.
{
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRXt4rxMN1+gTiWXD8bsTYlbx02ocBmIrEFD7kJGOwW github-actions-oci-edge"
  ];
}
