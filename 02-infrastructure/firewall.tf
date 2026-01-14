resource "proxmox_virtual_environment_cluster_firewall" "main" {
  enabled       = true
  input_policy  = "ACCEPT"
  output_policy = "ACCEPT"
}

# IPs that should have access to the NFS server
locals {
  nfs_client_ips = concat(
    [
      "10.10.1.41",          # tf-Pi4 REMOVE AFTER SWITCHING
      local.proxmox_host_ip, # nuc
      local.talos_controlplane_ip
    ],

    local.talos_worker_ips
  )
}

resource "proxmox_virtual_environment_firewall_options" "nfs_firewall_opts" {
  node_name    = var.proxmox_node
  container_id = proxmox_virtual_environment_container.nfs_server.vm_id

  enabled      = true
  input_policy = "DROP"

  dhcp     = true
  ipfilter = true
  ndp      = true
}

resource "proxmox_virtual_environment_firewall_ipset" "nfs_clients" {
  node_name    = var.proxmox_node
  container_id = proxmox_virtual_environment_container.nfs_server.vm_id
  name         = "nfs_clients"
  comment      = "Allowed NFS Clients"

  dynamic "cidr" {
    for_each = local.nfs_client_ips
    content {
      name = cidr.value
    }
  }
}

resource "proxmox_virtual_environment_firewall_rules" "nfs_rules" {
  node_name    = var.proxmox_node
  container_id = proxmox_virtual_environment_container.nfs_server.vm_id

  # Allow SSH
  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "22"
    comment = "SSH Management Access"
  }

  # Allow Full Access from Trusted Clients (K8s)
  rule {
    type    = "in"
    action  = "ACCEPT"
    source  = "+nfs_clients"
    comment = "Allow NFS access for K8s Workers and Pis"
  }
}
