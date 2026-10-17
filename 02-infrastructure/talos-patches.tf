# Machine-config patches shared by the node types
locals {
  talos_base_patches = [
    # Accept Vault-issued client certificates.
    yamlencode({
      machine = {
        acceptedCAs = [{ crt = base64encode(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.talos) }]
      }
      cluster = {
        acceptedCAs = [{ crt = base64encode(data.terraform_remote_state.vault.outputs.cluster_client_ca_pem.k8s) }]
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

  # Image Factory installer with the qemu-guest-agent extension, for the Proxmox VMs only.
  talos_vm_install_patch = yamlencode({
    machine = {
      install = {
        image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
      }
    }
  })

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
