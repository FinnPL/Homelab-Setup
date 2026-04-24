{ pkgs, ... }:

let
  # Render /etc/rancher/k3s/config.yaml before k3s starts. Fetches the OCI
  # instance OCID from IMDS and hands it to kubelet as `--provider-id`, so the
  # OCI CCM can map this Node to its compute instance. Without this, CCM falls
  # back to a degraded LB path that registers node backends at the listener
  # port (443/80) instead of the Service nodePort — which silently breaks all
  # Gateway/LoadBalancer traffic (TCP connects at the NLB, backend RSTs).
  k3sWriteOciConfig = pkgs.writeShellScript "k3s-write-oci-config" ''
    set -euo pipefail
    OCID=$(${pkgs.curl}/bin/curl -sSf --max-time 5 \
      -H "Authorization: Bearer Oracle" \
      http://169.254.169.254/opc/v2/instance/id)
    install -d -m 0755 /etc/rancher/k3s
    umask 077
    # No heredoc: Nix ''...'' strips the common leading indent at eval time,
    # so an indented heredoc terminator is only safe as long as every line in
    # the block shares that indent. A later unrelated edit that introduces a
    # less-indented line would change the strip amount and leave the "EOF"
    # marker with leftover whitespace, silently turning it into regular
    # heredoc body and breaking k3s startup. printf sidesteps it entirely.
    printf '%s\n' \
      'kubelet-arg:' \
      "  - \"provider-id=$OCID\"" \
      '  - "cloud-provider=external"' \
      > /etc/rancher/k3s/config.yaml
  '';
in
{
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--flannel-backend=none"           # Cilium replaces Flannel
      "--disable-network-policy"         # Cilium handles network policies
      "--disable=traefik"                # Gateway API replaces Traefik
      "--disable=servicelb"              # Cilium handles LoadBalancer
      "--disable-kube-proxy"             # Cilium handles kube-proxy replacement
      "--disable=local-storage"          # Not needed on edge node
      "--cluster-cidr=10.42.0.0/16"      # Non-overlapping with homelab (10.244.0.0/16)
      "--service-cidr=10.43.0.0/16"      # Non-overlapping with homelab (10.96.0.0/12)
      "--write-kubeconfig-mode=0600"     # Secure read since CI connects via root SSH
    ];
  };

  # Inject kubelet args dynamically via the config file (IMDS lookup at boot).
  systemd.services.k3s.serviceConfig.ExecStartPre = [ "${k3sWriteOciConfig}" ];

  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
  ];
}
