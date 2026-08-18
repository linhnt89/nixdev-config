# home/profiles/firstmate.nix — FIRSTMATE role profile (opt-in, tools only).
#
# A complete, importable Home Manager profile for a machine whose default job
# is running Firstmate: the portable common modules (shell/git/dev — same set
# as the other roles) plus the Firstmate toolchain module. Use it standalone
# via `lib.mkStandalone { role = "firstmate"; ... }` or import
# `homeManagerModules.firstmate` on top of any existing profile (laptop or
# desktop) — the tools simply layer on and same-store-path packages dedupe.
#
# Role note: this profile installs `gh` because Firstmate requires it, even on
# machines that would otherwise be handled by the glab-only laptop role. That
# is the explicit opt-in this profile represents; the default `laptop` and
# `desktop` profiles are untouched by it. See docs/firstmate.md.
{ lib, ... }:
{
  imports = [
    ../modules/shell.nix
    ../modules/git.nix
    ../modules/dev.nix
    ../modules/firstmate.nix
  ];

  # Home Manager state version for this profile's defaults; consumers may
  # override (mkDefault) when they manage their own migration policy.
  home.stateVersion = lib.mkDefault "26.05";
}