{
  description = "Shared terminal-only development environment for MetaCube (NixOS) and the work WSL2 laptop";

  # Phase 1: reproducible devShells. Phase 2 (implemented): portable,
  # parameterized Home Manager modules/profiles — the home-manager input
  # backs the exported `lib.mkStandalone` factory, the `homeManagerModules`
  # consumed later by nixos-config, and the pinned `home-manager` CLI
  # (docs/home-manager.md).
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving packages kept on a separate lane, mirroring the desktop
    # convention: the assistant lane (Pi) moves deliberately, not silently
    # with every stable bump.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # Home Manager pinned to the stable release matching nixos-26.05 and
    # forced onto this repo's nixpkgs pin, so devShell and Home Manager
    # packages come from the exact same nixpkgs revision (no drift).
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  # So a freshly installed Nix on the laptop works out of the box.
  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Single source of truth for every package list: devShells, the
      # Home Manager profiles, and the exported role modules all read
      # from lib/package-lists.nix.
      packageLists = import ./lib/package-lists.nix;

      mkShell = pkgs: packages: banner: 
        pkgs.mkShell {
          inherit packages;
          shellHook = ''
            echo "${banner}"
          '';
        };

      # Both machines (Arch WSL2 x86_64, MetaCube NixOS) are x86_64-linux;
      # this is the default target for the standalone Home Manager factory.
      hmSystem = "x86_64-linux";

      mkHomeConfiguration =
        {
          username,
          homeDirectory,
          system ? hmSystem,
          extraModules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          # Same stable pin as the devShells; pkgsUnstable is exposed for
          # the optional Pi assistant module (never configured here).
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          };
          modules = [
            {
              # Username and home directory are parameters, never
              # hard-coded — supplied by the caller (the personal wrapper
              # flake or nixos-config). Identity (git config, SSH hosts,
              # credentials) is never set here — docs/home-manager.md.
              home = {
                inherit username homeDirectory;
              };
            }
          ] ++ extraModules;
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          laptopShell = mkShell pkgs (packageLists.laptopPackages pkgs) packageLists.banners.laptop;
        in
        {
          # `nix develop` / direnv default = the laptop role.
          default = laptopShell;
          laptop = laptopShell;

          desktop = mkShell pkgs (packageLists.desktopPackages pkgs) packageLists.banners.desktop;

          assistant = mkShell pkgs (packageLists.assistantPackages pkgsUnstable) packageLists.banners.assistant;
        }
      );

      # The home-manager CLI pinned to this repo's home-manager input, so
      # `nix run .#home-manager -- switch --flake .#laptop` uses exactly
      # the release the configurations were built with.
      packages = forAllSystems (system: {
        home-manager = home-manager.packages.${system}.home-manager;
      });

      # Reusable portable Home Manager modules (NOT NixOS system modules).
      # - standalone: combined via lib.mkStandalone (see below) or imported
      #   by any personal flake
      # - NixOS side, in a later nixos-config PR:
      #     home-manager.users.<name>.imports = [ nixdev-config.homeManagerModules.desktop ... ]
      #   (or home-manager.extraModules)
      homeManagerModules = {
        shell = ./home/modules/shell.nix;
        git = ./home/modules/git.nix;
        dev = ./home/modules/dev.nix;
        assistant = ./home/modules/assistant.nix; # opt-in, unconfigured
        laptop = ./home/profiles/laptop.nix; # complete glab role profile
        desktop = ./home/profiles/desktop.nix; # complete gh role profile
      };

      # Parameterized standalone factory: builds a Home Manager
      # configuration for a concrete username/home directory/role without
      # editing any module file in this repo. The laptop wrapper flake
      # (docs/home-manager.md) looks like:
      #
      #   homeConfigurations.laptop = nixdev-config.lib.mkStandalone {
      #     username = "<actual-user>";
      #     homeDirectory = "/home/<actual-user>";
      #     role = "laptop";
      #   };
      lib.mkStandalone =
        {
          username,
          homeDirectory,
          role ? "laptop",
          system ? hmSystem,
          extraModules ? [ ],
        }:
        let
          profile =
            if role == "laptop" then ./home/profiles/laptop.nix
            else if role == "desktop" then ./home/profiles/desktop.nix
            else throw "nixdev-config: unknown role '${role}' — expected 'laptop' or 'desktop'";
        in
        mkHomeConfiguration {
          inherit username homeDirectory system;
          extraModules = extraModules ++ [ profile ];
        };
    };
}