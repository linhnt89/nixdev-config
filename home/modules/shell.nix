# home/modules/shell.nix — portable shell experience (shared base).
#
# This module installs the full *common* package set (the same list that
# backs the devShells — lib/package-lists.nix is the single source of
# truth, so shell and profile cannot drift) and configures the portable
# shell programs: zsh, starship, fzf, bat, eza.
#
# Importable from standalone Home Manager (Arch WSL2) and from Home
# Manager embedded in NixOS (a later nixos-config PR). Nothing here is
# user- or machine-specific: no identity, no credentials, no SSH host
# blocks, no provider/model settings (docs/home-manager.md).
{ pkgs, ... }:

let
  packageLists = import ../../lib/package-lists.nix;
in
{
  # Every package in the shared common set, from the same stable nixpkgs
  # pin the devShells use. Role-specific packages (glab/gh) are added by
  # the role profile, never here.
  home.packages = packageLists.commonPackages pkgs;

  # Zsh is configured but NOT forced as the login shell — changing the
  # login shell needs /etc/shells on the system side, which stays out of
  # the portable profile (optional, documented in docs/home-manager.md).
  # Bash integration is enabled below so the profile works even when the
  # login shell is still bash.
  programs.zsh.enable = true;

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    # settings stay portable defaults; theming is machine-local.
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.bat = {
    enable = true;
    # Portable defaults only — no machine-specific theme selection.
    config = {
      pager = "less -FR";
      theme = "TwoDark";
    };
  };

  programs.eza = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
  };
}