{ pkgs, ... }:

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
      "--write-kubeconfig-mode=0644"     # Readable for CI fetch
    ];
  };

  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
  ];
}
