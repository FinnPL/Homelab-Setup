resource "proxmox_virtual_environment_container" "vault_server" {
  description = "HashiCorp Vault Server"

  node_name = var.proxmox_node
  vm_id     = var.vault_server_config.vmid

  initialization {
    hostname = var.vault_server_config.name

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      password = var.vault_root_password
      keys     = [file(pathexpand(var.github_runner_ssh_public_key_path))]
    }
  }

  cpu {
    cores = var.vault_server_config.cores
  }

  memory {
    dedicated = var.vault_server_config.memory
  }

  disk {
    datastore_id = var.proxmox_storage
    size         = var.vault_server_config.disk_size
  }

  network_interface {
    name        = "eth0"
    bridge      = var.proxmox_bridge
    mac_address = local.vault_server_mac
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }

  startup {
    order = "2"
  }

  features {
    nesting = true
  }

  started = true
  tags    = ["security", "vault", "terraform"]

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "apt-get update",
      "apt-get install -y gpg wget lsb-release",
      
      # Install HashiCorp Repo
      "wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg",
      "echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" | tee /etc/apt/sources.list.d/hashicorp.list",
      
      # Install Vault
      "apt-get update",
      "apt-get install -y vault",

      # Create Data Directory
      "mkdir -p /opt/vault/data",
      "chown -R vault:vault /opt/vault",

      # Write Configuration
      "cat <<EOF > /etc/vault.d/vault.hcl",
      "ui = true",
      "disable_mlock = true",
      "",
      "storage \"raft\" {",
      "  path    = \"/opt/vault/data\"",
      "  node_id = \"node1\"",
      "}",
      "",
      "seal \"awskms\" {",
      "  region     = \"${var.aws_region}\"",
      "  kms_key_id = \"${aws_kms_key.vault_auto_unseal.key_id}\"",
      "  access_key = \"${aws_iam_access_key.vault_auto_unseal.id}\"",
      "  secret_key = \"${aws_iam_access_key.vault_auto_unseal.secret}\"",
      "}",
      "",
      "listener \"tcp\" {",
      "  address     = \"0.0.0.0:8200\"",
      "  tls_disable = 1", # Temporarily disable TLS for initial setup
      "}",
      "",
      "api_addr = \"http://${local.vault_server_ip}:8200\"",
      "cluster_addr = \"http://${local.vault_server_ip}:8201\"",
      "EOF",

      # Enable and Start
      "systemctl enable --now vault"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file(pathexpand(var.github_runner_ssh_private_key_path))
      host        = local.vault_server_ip
      timeout     = "5m"
    }
  }
}