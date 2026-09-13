{
  description = "Homelab development environment: Ansible, and the apps in apps/";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }: let
    system = builtins.currentSystem;
  in {
    devShells.aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
      packages = with nixpkgs.legacyPackages.aarch64-darwin; [
        ansible  
        ansible-lint 
        python3  
        python3Packages.pip  
        # apps/homelab-ios has no committed .xcodeproj; it is generated from
        # project.yml. Swift and xcodebuild come from Xcode, not from here.
        xcodegen
      ];
      shellHook = ''
        echo "Homelab dev shell ready (ansible, xcodegen)."
      '';
    };
  };
}
