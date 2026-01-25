data "github_actions_registration_token" "runner" {
  repository = var.github_repository
}

resource "proxmox_virtual_environment_file" "cloud_init_runner" {
  content_type = "snippets"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  source_raw {
    file_name = "cloud-init-runner-${var.github_runner_config.vmid}.yaml"
    data      = <<-EOF
      #cloud-config
      package_update: true
      package_upgrade: true
      packages:
        - qemu-guest-agent
        - docker.io
        - curl
        - ca-certificates
        - tar
      
      users:
        - name: ${var.github_runner_ssh_user}
          groups: sudo, docker
          shell: /bin/bash
          sudo: ['ALL=(ALL) NOPASSWD:ALL']
          ssh_authorized_keys:
            - ${trimspace(file(pathexpand(var.github_runner_ssh_public_key_path)))}

      runcmd:
        - systemctl enable --now qemu-guest-agent
        - systemctl enable --now docker
    EOF
  }
}

resource "proxmox_virtual_environment_vm" "github_runner" {
  name      = var.github_runner_config.name
  node_name = var.proxmox_node
  vm_id     = var.github_runner_config.vmid

  description = <<-EOT
    GitHub Actions self-hosted runner - Managed by Terraform
    Repo: ${var.github_owner}/${var.github_repository}
    IP: ${local.github_runner_ip}
    Network: Athena VLAN ${local.athena_vlan_id}
  EOT
  tags        = ["terraform", "github", "runner"]

  on_boot = true
  started = true

  clone {
    vm_id = var.github_runner_template_vmid
    full  = true
  }

  cpu {
    cores   = var.github_runner_config.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.github_runner_config.memory
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "scsi0"
    size         = var.github_runner_config.disk_size
  }

  network_device {
    bridge      = var.proxmox_bridge
    model       = "virtio"
    mac_address = local.github_runner_mac
  }

  agent {
    enabled = true
    type    = "virtio"
  }

  initialization {
    datastore_id = var.proxmox_storage
    interface    = "scsi1"

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_runner.id

  }

  lifecycle {
    ignore_changes = [
      started,
    ]
    #prevent_destroy = true
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        bash -lc "set -euo pipefail;
        # Wait for cloud-init to finish installing packages
        cloud-init status --wait;
        
        # Setup Runner Directory
        cd /home/${var.github_runner_ssh_user};
        sudo -u ${var.github_runner_ssh_user} mkdir -p actions-runner; 
        cd actions-runner;
        
        # Download and Configure
        sudo -u ${var.github_runner_ssh_user} curl -o actions-runner-linux-x64-${var.github_runner_version}.tar.gz -L https://github.com/actions/runner/releases/download/v${var.github_runner_version}/actions-runner-linux-x64-${var.github_runner_version}.tar.gz;
        sudo -u ${var.github_runner_ssh_user} tar xzf actions-runner-linux-x64-${var.github_runner_version}.tar.gz; 
        sudo -u ${var.github_runner_ssh_user} ./config.sh --url https://github.com/${var.github_owner}/${var.github_repository} --token ${data.github_actions_registration_token.runner.token} --name ${var.github_runner_config.name} --unattended --labels ${join(",", var.github_runner_labels)} --replace;
        
        # Install Service
        sudo ./svc.sh install; 
        sudo ./svc.sh start"
      EOT
    ]

    connection {
      type        = "ssh"
      user        = var.github_runner_ssh_user
      private_key = file(pathexpand(var.github_runner_ssh_private_key_path))
      host        = local.github_runner_ip
      timeout     = "10m"
    }
  }
}
