{
  description = "NixOS configurations for Minerva (Freiburg)";

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
      # NAS VM on the Minerva Proxmox host
      nas = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          disko.nixosModules.disko
          ./hosts/nas
        ];
      };
    };

    # Built on the target (remoteBuild)
    deploy.nodes.nas = {
      hostname = "10.10.1.11";
      sshUser = "root";
      remoteBuild = true;
      profiles.system.path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.nas;
    };
  };
}
