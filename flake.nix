{
  description = "NixOS module for the OwnTone audio server";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }: {
    nixosModules = {
      default = import ./modules/owntone.nix;
      owntone = self.nixosModules.default;
    };

    checks.x86_64-linux = import ./tests {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    };
  };
}
