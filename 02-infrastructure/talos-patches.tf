# Machine-config patches shared by the node types
locals {
  talos_base_patches = [
    # Accept Vault-issued client certificates.
    yamlencode({
      machine = {
        acceptedCAs = [{ crt = base64encode("${chomp(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.talos)}\n") }]
      }
      cluster = {
        acceptedCAs = [{ crt = base64encode("${chomp(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.k8s)}\n") }]
      }
    }),
    yamlencode({
      machine = {
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
      }
    }),
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
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
  ]

  # Image Factory installer: qemu-guest-agent on the Proxmox VMs, the Raspberry Pi overlay on the Pis.
  talos_install_patch = {
    for kind, schematic in { vm = talos_image_factory_schematic.this.id, pi = talos_image_factory_schematic.pi.id } : kind => yamlencode({
      machine = {
        install = {
          image = "factory.talos.dev/installer/${schematic}:${local.talos_version}"
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
