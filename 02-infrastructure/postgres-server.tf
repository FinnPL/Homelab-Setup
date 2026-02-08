resource "proxmox_virtual_environment_container" "postgres_server" {
  description = "Shared PostgreSQL Database Server"

  node_name = var.proxmox_node
  vm_id     = var.postgres_server_config.vmid

  initialization {
    hostname = var.postgres_server_config.name

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      password = var.postgres_root_password
      keys     = [file(pathexpand(var.github_runner_ssh_public_key_path))]
    }
  }

  cpu {
    cores = var.postgres_server_config.cores
  }

  memory {
    dedicated = var.postgres_server_config.memory
  }

  disk {
    datastore_id = var.proxmox_storage
    size         = var.postgres_server_config.disk_size
  }

  network_interface {
    name        = "eth0"
    bridge      = var.proxmox_bridge
    mac_address = local.host_vm_macs.postgres_server
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
  tags    = ["database", "postgres", "terraform"]

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "exec > /tmp/terraform_debug.log 2>&1",
      "apt-get update",
      "apt-get install -y postgresql postgresql-contrib",

      "sed -i \"s/#listen_addresses = 'localhost'/listen_addresses = '*' /\" /etc/postgresql/*/main/postgresql.conf",

      "echo 'host  all  all  ${local.athena_subnet}  scram-sha-256' | tee -a /etc/postgresql/*/main/pg_hba.conf",

      "systemctl restart postgresql",

      "sudo -u postgres psql -c \"ALTER USER postgres PASSWORD '${var.postgres_admin_password}';\""
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file(pathexpand(var.github_runner_ssh_private_key_path))
      host        = local.postgres_server_ip
      timeout     = "5m"
    }
  }
}
