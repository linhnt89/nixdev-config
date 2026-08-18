# home/modules/firstmate.nix — OPTIONAL Firstmate toolchain module.
#
# Importing this module IS the explicit opt-in: it installs the tools the
# Firstmate bootstrap requires on top of whatever profile it is added to
# (docs/firstmate.md). It is never imported by the default `laptop` or
# `desktop` profiles, so the role split is unchanged: the laptop profile stays
# glab-only (no `gh`) and the desktop profile stays gh-only (no `glab`) unless
# you deliberately add this module. Because Firstmate currently requires `gh`
# on every home, this module adds `pkgs.gh` — that is the documented,
# explicit exception to the role split.
#
# Tool supply only, nothing else: no Firstmate source, no data/state/config,
# no credentials, no remotes, no provider/model settings. Firstmate's runtime
# state stays in its own separate repository/home; the bootstrap's
# `gh auth login` stores credentials locally.
#
# Installable from standalone Home Manager (laptop) and from Home Manager
# embedded in NixOS (desktop's nixos-config PR later); the parameters come
# from the caller — nothing here is user- or machine-specific.
#
# Where the required `treehousePkg` argument comes from:
#   - standalone callers through `lib.mkStandalone`: wired automatically by
#     the flake's factory.
#   - external NixOS Home Manager callers: explicitly, via extraSpecialArgs,
#     using ONLY this flake's public package output — no second treehouse
#     flake input on the consumer side (docs/firstmate.md):
#
#         home-manager.extraSpecialArgs.treehousePkg =
#           nixdev-config.packages.${pkgs.system}.treehouse;
{ config, lib, pkgs, treehousePkg, ... }:

let
  firstmate = import ../../lib/firstmate.nix {
    inherit pkgs treehousePkg;
  };

  cfg = config.nixdev.firstmate;
in
{
  options.nixdev.firstmate = {
    # Optional Herdr backend. Firstmate's default backend is tmux (installed
    # by this module); a machine that opts into the experimental Herdr backend
    # needs the pinned herdr binary too. This is a pinned dependency choice:
    # NO Herdr lifecycle (start/stop/sessions) is ever driven from Nix — the
    # binary is installed, and firstmate runs it through its own bootstrap.
    enableHerdr = lib.mkEnableOption ''
      the pinned Herdr backend binary (v0.8.0 release asset; requires jq,
      already provided). Default backend remains tmux.
    '';
  };

  config = {
    # The full Firstmate toolchain for the reference (tmux) workflow.
    home.packages = firstmate.packages
      ++ lib.optionals cfg.enableHerdr [ firstmate.herdr ];
  };
}