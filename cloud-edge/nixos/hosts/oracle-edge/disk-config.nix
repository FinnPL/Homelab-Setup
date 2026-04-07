{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda"; # OCI ARM A1 uses virtio-scsi (/dev/sda). x86 shapes may use /dev/nvme0n1.
    content = {
      type = "gpt";
      partitions = {

        # EFI System Partition
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        # Root filesystem
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };

      };
    };
  };
}
