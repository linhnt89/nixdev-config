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

    # Firstmate toolchain sources (docs/firstmate.md). treehouse is pinned to
    # the upstream flake at tag v2.1.1 (Go source build, Nix-patched so it
    # runs on NixOS); its nixpkgs follows the unstable lane. herdr and
    # no-mistakes use pinned release assets inside lib/firstmate.nix instead
    # (statically linked binaries, no flake input needed).
    treehouse.url = "github:kunchenguid/treehouse/v2.3.0";
    treehouse.inputs.nixpkgs.follows = "nixpkgs-unstable";
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
      treehouse,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Single source of truth for every package list: devShells, the
      # Home Manager profiles, and the exported role modules all read
      # from lib/package-lists.nix. The optional Firstmate toolchain lives
      # in its own shared lib (lib/firstmate.nix) because it needs the npm
      # lockfile root and pinned external binaries, not just pkgs.
      packageLists = import ./lib/package-lists.nix;

      # Resolves the shared Firstmate toolchain for a system: same pieces
      # for the devShell and the Home Manager module (no drift).
      firstmateTools = system:
        import ./lib/firstmate.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          treehousePkg = treehousePkg system;
        };

      # The pinned treehouse package for a system — the single source behind
      # the exported `packages.${system}.treehouse` output AND what
      # mkHomeConfiguration injects into the Firstmate module internally.
      # External consumers (nixos-config) pass the exported package via
      # explicit extraSpecialArgs (docs/firstmate.md); standalone callers get
      # it wired automatically by lib.mkStandalone. No consumer ever needs
      # its own treehouse flake input.
      treehousePkg = system: treehouse.packages.${system}.default;

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
            # Same package as the exported packages.${system}.treehouse —
            # internal wiring for lib.mkStandalone; external consumers pass
            # the export themselves via extraSpecialArgs (docs/firstmate.md).
            treehousePkg = treehousePkg system;
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
          firstmateShell = firstmateTools system;
        in
        {
          # `nix develop` / direnv default = the laptop role.
          default = laptopShell;
          laptop = laptopShell;

          desktop = mkShell pkgs (packageLists.desktopPackages pkgs) packageLists.banners.desktop;

          assistant = mkShell pkgs (packageLists.assistantPackages pkgsUnstable) packageLists.banners.assistant;

          # Ephemeral Firstmate toolchain (same build as the opt-in Home
          # Manager profile — lib/firstmate.nix is the single source).
          firstmate = mkShell pkgs firstmateShell.packages firstmateShell.banner;
        }
      );

      # Consumer-facing package outputs.
      # - home-manager: the CLI pinned to this repo's home-manager input, so
      #   `nix run .#home-manager -- switch --flake .#laptop` uses exactly
      #   the release the configurations were built with.
      # - treehouse: the pinned Firstmate worktree provider (flake input at
      #   tag v2.1.1, docs/firstmate.md). This is the stable, documented way
      #   for a consumer of homeManagerModules.firstmateTools to obtain the
      #   package without declaring a second treehouse flake input:
      #
      #       home-manager.extraSpecialArgs.treehousePkg =
      #         nixdev-config.packages.${system}.treehouse;
      #
      #   Standalone callers never touch this — lib.mkStandalone wires the
      #   same package internally.
      packages = forAllSystems (system: {
        home-manager = home-manager.packages.${system}.home-manager;
        treehouse = treehousePkg system;
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
        firstmateTools = ./home/modules/firstmate.nix; # opt-in toolchain layer
        laptop = ./home/profiles/laptop.nix; # complete glab role profile
        desktop = ./home/profiles/desktop.nix; # complete gh role profile
        firstmate = ./home/profiles/firstmate.nix; # opt-in firstmate role profile
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
            else if role == "firstmate" then ./home/profiles/firstmate.nix
            else throw "nixdev-config: unknown role '${role}' — expected 'laptop', 'desktop', or 'firstmate'";
        in
        mkHomeConfiguration {
          inherit username homeDirectory system;
          extraModules = extraModules ++ [ profile ];
        };
    };
}