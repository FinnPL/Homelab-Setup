{
  description = "NixOS configurations for Homelab cloud nodes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/f37d14db4e7f801872506a2dee5cce5da36ea512";

    disko = {
      url = "github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1";
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
