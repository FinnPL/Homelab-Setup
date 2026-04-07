# nixos-anywhere will generate a more complete version on first install
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "virtio_net"
  ];

  boot.kernelParams = [
    "console=ttyS0,115200n8" # OCI Serial Console
    "net.ifnames=0"          # Predictable eth0 naming
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
}
