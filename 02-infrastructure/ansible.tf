resource "local_sensitive_file" "ansible_ssh_key" {
  content         = var.proxmox_ssh_private_key
  filename        = "${path.module}/.ansible/ssh_key"
  file_permission = "0600"
}
