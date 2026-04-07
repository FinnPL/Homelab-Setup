# Placeholder module kept in git so flake source always includes this file.
# CI overwrites it during deploy with OCI_SSH_PUBLIC_KEY.
{
  users.users.root.openssh.authorizedKeys.keys = [ ];
}
