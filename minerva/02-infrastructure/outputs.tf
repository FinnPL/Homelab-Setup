output "nas" {
  description = "The NAS VM"
  value = {
    vmid    = proxmox_virtual_environment_vm.nas.vm_id
    address = split("/", var.nas_vm.address)[0]
  }
}
