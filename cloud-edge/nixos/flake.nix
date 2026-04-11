{
  description = "NixOS configurations for Homelab cloud nodes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/039582a0945f94a390c4ce7e93ebfb8b3b86a598";

    disko = {
      url = "github:nix-community/disko/5ad85c82cc52264f4beddc934ba57f3789f28347";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }@inputs: {
    nixosConfigurations = {

      # Oracle Cloud Always Free ARM edge node
      oracle-edge = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          ./hosts/oracle-edge
        ];
      };

    };
  };
}
