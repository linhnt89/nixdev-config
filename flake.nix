{
  description = "Shared terminal-only development environment for MetaCube (NixOS) and the work WSL2 laptop";

  # Phase 1 scope: reproducible devShells only. Home Manager integration
  # (standalone, parameterized) is a documented Phase 2 item; the home-manager
  # input is deliberately NOT added until a homeConfigurations output exists.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving packages kept on a separate lane, mirroring the desktop
    # convention: the assistant lane (Pi) moves deliberately, not silently
    # with every stable bump.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # ---------------------------------------------------------------------
      # Common terminal-only toolset shared by every role.
      #
      # Justification (from the Phase 1 scout report): Git/SSH, shell/CLI
      # utilities, text/search/data tools, direnv/nix-direnv, Node tooling,
      # and script validation. No GUI, no system services, no credentials.
      # ---------------------------------------------------------------------
      commonPackages = pkgs: [
        # Git + SSH
        pkgs.gitFull
        pkgs.openssh

        # Shell / CLI utilities
        pkgs.delta # diff pager; git integration via ~/.gitconfig (local)
        pkgs.eza # ls replacement
        pkgs.fzf # fuzzy finder
        pkgs.lazygit # terminal git TUI
        pkgs.tree
        pkgs.zip
        pkgs.unzip
        pkgs.curl
        pkgs.wget

        # Text / search / data
        pkgs.bat
        pkgs.fd
        pkgs.ripgrep
        pkgs.jq
        pkgs.yq-go

        # Project environments
        pkgs.direnv
        pkgs.nix-direnv

        # Node tooling (npm ships with nodejs)
        pkgs.nodejs

        # Task runner / script validation
        pkgs.just
        pkgs.shellcheck
      ];

      # Work WSL2 laptop role: company GitLab is the push/pull destination,
      # so this shell ships `glab`. GitHub stays read-only (public sources)
      # and is NOT installed here — get `gh` on demand with:
      #   nix shell nixpkgs#gh
      laptopPackages = pkgs: commonPackages pkgs ++ [ pkgs.glab ];

      # MetaCube desktop role: GitHub is the personal push/pull destination,
      # so this shell ships `gh`. No git-hosting CLI beyond that.
      desktopPackages = pkgs: commonPackages pkgs ++ [ pkgs.gh ];

      # Optional assistant shell: Pi only, and with NO provider/model
      # configuration shipped — the local llama.cpp fallback and any cloud
      # provider are configured at runtime in ~/.pi/agent, never here.
      # Claude Code is intentionally NOT packaged (see docs/claude-code.md).
      assistantPackages = pkgsUnstable: [
        pkgsUnstable.pi-coding-agent
      ];

      # ------ role banners -------------------------------------------------

      laptopBanner = ''
        __ nixdev-config — laptop role (Arch WSL2) ________________________
          Git hosting CLI : glab (company GitLab — push/pull home)
          GitHub         : read-only, on demand (nix shell nixpkgs#gh)
          Remotes/creds  : configured locally (~/.gitconfig, ~/.ssh,
                           glab auth login) — never in Nix.
          Docs           : docs/git-workflow.md, docs/wsl2-prerequisites.md
        __________________________________________________________________
      '';

      desktopBanner = ''
        __ nixdev-config — desktop role (MetaCube NixOS) __________________
          Git hosting CLI : gh (GitHub — push/pull home)
          Remotes/creds  : configured locally (~/.gitconfig, ~/.ssh,
                           `gh auth login`) — never in Nix.
          Docs           : docs/git-workflow.md
        __________________________________________________________________
      '';

      assistantBanner = ''
        __ nixdev-config — optional assistant shell (Pi) __________________
          Pi binary only; no provider/model configured by this repo.
          Local fallback: `pi login llama.cpp` (default router
          http://127.0.0.1:8080). Runtime state lives in ~/.pi/agent (0600).
          Docs           : docs/assistant-tooling.md
        __________________________________________________________________
      '';

      mkShell = pkgs: packages: banner: 
        pkgs.mkShell {
          inherit packages;
          shellHook = ''
            echo "${banner}"
          '';
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          laptopShell = mkShell pkgs (laptopPackages pkgs) laptopBanner;
        in
        {
          # `nix develop` / direnv default = the laptop role.
          default = laptopShell;
          laptop = laptopShell;

          desktop = mkShell pkgs (desktopPackages pkgs) desktopBanner;

          assistant = mkShell pkgs (assistantPackages pkgsUnstable) assistantBanner;
        }
      );
    };
}