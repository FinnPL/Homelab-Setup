{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda"; # Proxmox virtio-scsi
    content = {
      type = "gpt";
      partitions = {
        # GRUB core image for BIOS boot on GPT
        boot = {
          size = "1M";
          type = "EF02";
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            # The disk is throttled to 20 MB/s.
            extraArgs = ["-E" "nodiscard"];
            mountpoint = "/";
          };
        };
      };
    };
  };
}
