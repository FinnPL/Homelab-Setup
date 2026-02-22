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

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(pathexpand(var.github_runner_ssh_private_key_path))
    host        = local.vault_server_ip
    timeout     = "5m"
  }

  provisioner "file" {
    content     = "${tls_locally_signed_cert.vault_server.cert_pem}\n${tls_self_signed_cert.vault_ca.cert_pem}"
    destination = "/tmp/vault.crt"
  }

  provisioner "file" {
    content     = tls_private_key.vault_server.private_key_pem
    destination = "/tmp/vault.key"
  }

  provisioner "file" {
    content     = <<-EOF
      ui = true
      disable_mlock = true

      storage "raft" {
        path    = "/opt/vault/data"
        node_id = "node1"
      }

      seal "awskms" {
        region     = "${var.aws_region}"
        kms_key_id = "${aws_kms_key.vault_auto_unseal.key_id}"
        access_key = "${aws_iam_access_key.vault_auto_unseal.id}"
        secret_key = "${aws_iam_access_key.vault_auto_unseal.secret}"
      }

      listener "tcp" {
        address       = "0.0.0.0:8200"
        tls_cert_file = "/etc/vault.d/tls/vault.crt"
        tls_key_file  = "/etc/vault.d/tls/vault.key"
      }

      api_addr     = "https://${local.vault_server_ip}:8200"
      cluster_addr = "https://${local.vault_server_ip}:8201"
    EOF
    destination = "/tmp/vault.hcl"
  }

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
      "mkdir -p /etc/vault.d/tls",
      "chown -R vault:vault /opt/vault",

      # Install Terraform-Managed TLS Certificate
      "mv /tmp/vault.crt /etc/vault.d/tls/vault.crt",
      "mv /tmp/vault.key /etc/vault.d/tls/vault.key",
      "chown -R vault:vault /etc/vault.d/tls",
      "chmod 640 /etc/vault.d/tls/vault.key",
      "chmod 644 /etc/vault.d/tls/vault.crt",

      # Write Configuration
      "mv /tmp/vault.hcl /etc/vault.d/vault.hcl",
      "chown vault:vault /etc/vault.d/vault.hcl",

      # Enable and Start
      "systemctl enable --now vault"
    ]
  }
}