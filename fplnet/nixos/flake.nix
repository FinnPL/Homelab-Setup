{
  description = "NixOS configurations for the AS218255 (FPLNET) routers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    disko,
    deploy-rs,
    ...
  } @ inputs: let
    deployPkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        deploy-rs.overlays.default
        (_: super: {
          deploy-rs = {
            inherit (nixpkgs.legacyPackages.x86_64-linux) deploy-rs;
            inherit (super.deploy-rs) lib;
          };
        })
      ];
    };
  in {
    nixosConfigurations = {
      # Servperso Düsseldorf BGP edge
      er1-dus1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          disko.nixosModules.disko
          ./hosts/er1-dus1
        ];
      };

      # getvps.net Amsterdam BGP edge
      er1-ams1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          disko.nixosModules.disko
          ./hosts/er1-ams1
        ];
      };
    };

    # CI deploys every router in ../hosts.json
    deploy.nodes =
      builtins.mapAttrs (name: host: {
        hostname = host.ssh;
        sshUser = "root";
        profiles.system.path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
      })
      (builtins.fromJSON (builtins.readFile ../hosts.json));
  };
}
