{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ../../modules/base.nix
    ../../modules/zfs.nix
    ../../modules/backup-pull.nix
    ../../modules/monitoring.nix
  ];

  networking = {
    hostName = "nas";
    domain = "minerva.lippok.dev";
    hostId = "2fd3dd8a";
  };

  # On Vieta's Athena VLAN until the move to Freiburg
  systemd.network.networks."10-lan" = {
    matchConfig.Type = "ether";
    address = ["10.10.1.11/24"];
    routes = [{Gateway = "10.10.1.1";}];
    dns = ["10.10.1.1"];
    networkConfig.IPv6AcceptRA = false;
  };

  minerva.monitoring.scrapeSources = ["10.10.1.0/24"];

  # Synology DSM
  minerva.backupPulls.apollo = {
    host = "10.10.1.195";
    user = "minerva-pull";
    knownHosts = ../../files/apollo_known_hosts;
    paths = [];
    # DSM thumbnails/metadata, recycle bins and its own snapshots.
    excludes = ["@eaDir" "#recycle" "#snapshot"];
  };
}
