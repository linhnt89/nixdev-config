# home/profiles/desktop.nix — DESKTOP (personal, MetaCube NixOS) role profile.
#
# A complete, importable Home Manager profile for the desktop role: the
# portable common modules plus the `gh` Git hosting CLI. Used by
# `homeConfigurations.desktop` for standalone use/tests and by the later
# nixos-config PR as the desktop's NixOS-side Home Manager module set.
#
# Role split: this profile installs gh and NEVER glab. The desktop's
# personal pushes go to GitHub; GitLab stays out — see docs/git-workflow.md.
{ lib, pkgs, ... }:
{
  imports = [
    ../modules/shell.nix
    ../modules/git.nix
    ../modules/dev.nix
  ];

  # Home Manager state version for this profile's defaults; consumers may
  # override (mkDefault) when they manage their own migration policy.
  home.stateVersion = lib.mkDefault "26.05";

  # Role: GitHub is this machine's push/pull destination.
  home.packages = [ pkgs.gh ];
}