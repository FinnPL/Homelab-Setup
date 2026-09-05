{
  description = "NixOS configurations for Homelab cloud nodes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/a896b510a0794f7bae5640bdb7412b60b0c5e5eb";

    disko = {
      url = "github:nix-community/disko/5ad85c82cc52264f4beddc934ba57f3789f28347";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    ...
  } @ inputs: {
    nixosConfigurations = {
      # Oracle Cloud Always Free ARM edge node
      oracle-edge = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          disko.nixosModules.disko
          ./hosts/oracle-edge
        ];
      };
    };
  };
}
