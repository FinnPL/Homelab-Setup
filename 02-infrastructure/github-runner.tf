data "github_actions_registration_token" "runner" {
  repository = var.github_repository
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
    bridge  = var.proxmox_bridge
    model   = "virtio"
    vlan_id = local.athena_vlan_id
  }

  agent {
    enabled = true
    type    = "virtio"
  }

  initialization {
    datastore_id = var.proxmox_storage
    interface    = "scsi1"

    user_account {
      username = var.github_runner_ssh_user
      keys     = [file(pathexpand(var.github_runner_ssh_public_key_path))]
    }

    ip_config {
      ipv4 {
        address = "${local.github_runner_ip}/${local.athena_subnet_cidr}"
        gateway = local.athena_gateway
      }
    }

    dns {
      servers = [local.athena_gateway]
    }
  }

  lifecycle {
    ignore_changes = [
      started,
    ]
    prevent_destroy = true
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
        bash -lc "set -euo pipefail; trap 'echo runner bootstrap failed at line $LINENO >&2' ERR; sudo apt-get update; sudo apt-get install -y curl ca-certificates tar docker.io; sudo systemctl enable --now docker; cd /home/${var.github_runner_ssh_user}; sudo -u ${var.github_runner_ssh_user} mkdir -p actions-runner; cd /home/${var.github_runner_ssh_user}/actions-runner; sudo -u ${var.github_runner_ssh_user} curl -o actions-runner-linux-x64-${var.github_runner_version}.tar.gz -L https://github.com/actions/runner/releases/download/v${var.github_runner_version}/actions-runner-linux-x64-${var.github_runner_version}.tar.gz; sudo -u ${var.github_runner_ssh_user} tar xzf actions-runner-linux-x64-${var.github_runner_version}.tar.gz; sudo -u ${var.github_runner_ssh_user} ./config.sh --url https://github.com/${var.github_owner}/${var.github_repository} --token ${data.github_actions_registration_token.runner.token} --name ${var.github_runner_config.name} --unattended --labels ${join(",", var.github_runner_labels)}; sudo ./svc.sh install; sudo ./svc.sh start"
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
