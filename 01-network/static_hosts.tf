resource "unifi_user" "tf_apollo_host" {
  mac              = "00:11:32:7f:65:e3"
  name             = "tf-Apollo-NAS"
  fixed_ip         = "10.10.1.195"
  local_dns_record = "apollo.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_pi4_host" {
  mac              = "dc:a6:32:1f:b3:fb"
  name             = "tf-Pi4"
  fixed_ip         = "10.10.1.41"
  local_dns_record = "pi4.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_nuc_host" {
  mac              = "94:c6:91:18:9c:aa"
  name             = "tf-Intel-NUC"
  fixed_ip         = "10.10.1.42"
  local_dns_record = "nuc.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_windows_server" {
  mac              = var.host_vm_macs["windows_server"]
  name             = "tf-Windows-Server"
  fixed_ip         = "10.10.1.50"
  local_dns_record = "win.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_controlplane" {
  mac              = var.host_vm_macs["talos_controlplane"]
  name             = "tf-Talos-ControlPlane"
  fixed_ip         = "10.10.1.60"
  local_dns_record = "talos-cp.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_github_runner" {
  mac              = var.host_vm_macs["github_runner"]
  name             = "tf-GitHub-Runner"
  fixed_ip         = "10.10.1.70"
  local_dns_record = "runner.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_nfs_server" {
  mac              = var.host_vm_macs["nfs_server"]
  name             = "tf-NFS-Server"
  fixed_ip         = "10.10.1.80"
  local_dns_record = "nfs.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_worker_1" {
  mac              = "dc:a6:32:af:be:2f"
  name             = "tf-Talos-Worker-1"
  fixed_ip         = "10.10.1.61"
  local_dns_record = "talos-w1.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_worker_2" {
  mac              = "dc:a6:32:4a:11:70"
  name             = "tf-Talos-Worker-2"
  fixed_ip         = "10.10.1.62"
  local_dns_record = "talos-w2.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_worker_3" {
  mac              = "bc:24:11:00:00:63" #placeholder 
  name             = "tf-Talos-Worker-3"
  fixed_ip         = "10.10.1.63"
  local_dns_record = "talos-w3.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_worker_4" {
  mac              = "bc:24:11:00:00:64" #placeholder
  name             = "tf-Talos-Worker-4"
  fixed_ip         = "10.10.1.64"
  local_dns_record = "talos-w4.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_talos_worker_5" {
  mac              = "bc:24:11:00:00:65" #placeholder
  name             = "tf-Talos-Worker-5"
  fixed_ip         = "10.10.1.65"
  local_dns_record = "talos-w5.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}
