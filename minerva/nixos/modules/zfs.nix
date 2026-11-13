# The nas pool: imported at boot, scrubbed monthly, nas/backup snapshotted by sanoid.
# The pool is a mirror of two ST8000NM0075
{
  boot = {
    supportedFilesystems = ["zfs"];
    zfs = {
      extraPools = ["nas"];
      forceImportRoot = false;
    };
  };

  services.zfs = {
    # Spinning disks, nothing to trim.
    trim.enable = false;
    autoScrub = {
      enable = true;
      interval = "monthly";
      pools = ["nas"];
    };
    zed.settings.ZED_NOTIFY_VERBOSE = true;
  };

  services.sanoid = {
    enable = true;
    templates.backup = {
      hourly = 24;
      daily = 30;
      monthly = 6;
      autosnap = true;
      autoprune = true;
    };
    datasets."nas/backup" = {
      useTemplate = ["backup"];
      recursive = true;
    };
  };

  # Short self-test Sundays 03:00, long (about 14 h on 8 TB) on the 15th at 04:00
  services.smartd = {
    enable = true;
    defaults.autodetected = "-a -s (S/../../7/03|L/../15/./04)";
    notifications.wall.enable = false;
  };
}
