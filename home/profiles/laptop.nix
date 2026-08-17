# home/profiles/laptop.nix — LAPTOP (work, Arch WSL2) role profile.
#
# A complete, importable Home Manager profile for the laptop role: the
# portable common modules plus the `glab` Git hosting CLI. It is the
# standalone shape used by `homeConfigurations.laptop` and the module
# imported by nixos-config later for the desktop's NixOS-side Home
# Manager integration (only the desktop profile is used there).
#
# Role split: this profile installs glab and NEVER gh. GitHub stays
# read-only and on-demand on the laptop (`nix shell nixpkgs#gh`) —
# see docs/git-workflow.md.
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

  # Role: company GitLab is this machine's push/pull destination.
  home.packages = [ pkgs.glab ];
}