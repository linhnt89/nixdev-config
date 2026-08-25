# lib/package-lists.nix — single source of truth for the shell packages.
#
# Imported by flake.nix (for the devShells) and by the portable Home
# Manager modules (for `home.packages`), so the devShell and Home Manager
# profiles read the exact same package lists against the exact same
# nixpkgs pin and cannot silently drift.
#
# Every list is a function `pkgs: [ ... ]`; callers supply the package
# set. The devShells and HM profiles use the stable `nixpkgs` input; the
# assistant lane alone uses `nixpkgs-unstable` (docs/updates.md).
#
# Terminal-only boundary: no GUI, no system services, no credentials —
# enforced by the module comments and scripts/check.sh's no-secrets scan.
rec {
  # ---------------------------------------------------------------------
  # Common terminal-only toolset shared by every role/profile.
  #
  # Justification (from the Phase 1 scout report): Git/SSH, shell/CLI
  # utilities, text/search/data tools, direnv/nix-direnv, Node + Python
  # language tooling, and script validation. No GUI, no system services,
  # no credentials.
  # ---------------------------------------------------------------------
  commonPackages = pkgs: [
    # Git + SSH
    pkgs.gitFull
    pkgs.openssh

    # Shell / CLI utilities
    pkgs.diffutils # cmp / diff
    pkgs.delta # diff pager; git integration via the HM git module
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

    # Native build toolchain
    pkgs.gcc
    pkgs.gnumake

    # Language tooling
    pkgs.nodejs # npm ships with nodejs
    pkgs.python3 # standard Python interpreter; also the YAML parse step in
    # scripts/check.sh uses python3/PyYAML when present

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

  # Optional assistant shell/profile: Pi only, and with NO provider/model
  # configuration shipped — the local llama.cpp fallback and any cloud
  # provider are configured at runtime in ~/.pi/agent, never here.
  # Claude Code is intentionally NOT packaged (see docs/claude-code.md).
  assistantPackages = pkgsUnstable: [
    pkgsUnstable.pi-coding-agent
  ];

  # Role banners for the devShells (the HM profiles carry their role in
  # the docs instead of shell banners). Structure only — no secrets.
  banners = {
    laptop = ''
      __ nixdev-config — laptop role (Arch WSL2) ________________________
        Git hosting CLI : glab (company GitLab — push/pull home)
        GitHub         : read-only, on demand (nix shell nixpkgs#gh)
        Remotes/creds  : configured locally (~/.gitconfig, ~/.ssh,
                         glab auth login) — never in Nix.
        Docs           : docs/git-workflow.md, docs/wsl2-prerequisites.md
      __________________________________________________________________
    '';

    desktop = ''
      __ nixdev-config — desktop role (MetaCube NixOS) __________________
        Git hosting CLI : gh (GitHub — push/pull home)
        Remotes/creds  : configured locally (~/.gitconfig, ~/.ssh,
                         `gh auth login`) — never in Nix.
        Docs           : docs/git-workflow.md
      __________________________________________________________________
    '';

    assistant = ''
      __ nixdev-config — optional assistant shell (Pi) __________________
        Pi binary only; no provider/model configured by this repo.
        Local fallback: `pi login llama.cpp` (default router
        http://127.0.0.1:8080). Runtime state lives in ~/.pi/agent (0600).
        Docs           : docs/assistant-tooling.md
      __________________________________________________________________
    '';
  };
}