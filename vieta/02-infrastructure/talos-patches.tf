# Machine-config patches shared by the node types
locals {
  # Dual-stack.
  # The controller-manager gives each node a /24 and a /64.
  # ClusterIPs come from the site's ULA.
  k8s_pod_subnets     = ["10.244.0.0/16", "2a0c:b641:f94:8100::/56"]
  k8s_service_subnets = ["10.96.0.0/12", "fd84:d57e:6e57:4100::/112"]

  k8s_cluster_dns = [cidrhost(local.k8s_service_subnets[0], 10)]

  vieta_v6_lan     = "2a0c:b641:f94:20::/64"
  vieta_v6_gateway = "2a0c:b641:f94:20::1" # gw1-aah1

  talos_base_patches = [
    # Accept Vault-issued client certificates.
    yamlencode({
      machine = {
        acceptedCAs = [{ crt = base64encode("${chomp(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.talos)}\n") }]
      }
    }),
    yamlencode({
      apiVersion  = "v1alpha1"
      kind        = "KubeAPIServerCAConfig"
      acceptedCAs = ["${chomp(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.k8s)}\n"]
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
    yamlencode({
      machine = {
        logging = {
          destinations = [
            {
              endpoint = "udp://127.0.0.1:5140"
              format   = "json_lines"
            }
          ]
        }
      }
    }),
    yamlencode({
      apiVersion     = "v1alpha1"
      kind           = "KubeNetworkConfig"
      podSubnets     = local.k8s_pod_subnets
      serviceSubnets = local.k8s_service_subnets
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      nodeIP = {
        validSubnets = [local.athena_subnet, local.vieta_v6_lan]
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeletConfig"
      clusterDNS = local.k8s_cluster_dns
    }),
  ]

  # Athena has no router advertisements, so each node gets a static IPv6 address,
  # f94:20::<last IPv4 octet> (list in fplnet/nixos/hosts/gw1-aah1/bgp.nix)
  # gw1-aah1 as its default route.
  talos_v6_nodes = {
    for ip, nic in merge(
      { (local.talos_controlplane_ip) = "ens18", (local.talos_db_worker_ip) = "ens18" },
      { for ip in local.talos_worker_ips : ip => "end0" },
      ) : ip => {
      nic     = nic
      address = "2a0c:b641:f94:20::${split(".", ip)[3]}"
    }
  }

  talos_v6_patches = {
    for ip, node in local.talos_v6_nodes : ip => [
      yamlencode({
        machine = {
          network = {
            interfaces = [
              {
                interface = node.nic
                addresses = ["${node.address}/64"]
                routes = [
                  {
                    network = "::/0"
                    gateway = local.vieta_v6_gateway
                  }
                ]
              }
            ]
          }
        }
      }),
    ]
  }

  # Image Factory installer: qemu-guest-agent on the Proxmox VMs, the Raspberry Pi overlay on the Pis.
  talos_install_patch = {
    for kind, schematic in { vm = talos_image_factory_schematic.this.id, pi = talos_image_factory_schematic.pi.id } : kind => yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = "factory.talos.dev/installer/${schematic}:${local.talos_version}"
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
      }
    })
  }

  # Uplink NIC: virtio on the Proxmox VMs, onboard ethernet on the Pis.
  talos_nic_patch = {
    for kind, nic in { vm = "ens18", pi = "end0" } : kind => yamlencode({
      machine = {
        network = {
          interfaces = [
            {
              interface = nic
              dhcp      = true
            }
          ]
        }
      }
    })
  }
}
