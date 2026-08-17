# home/modules/assistant.nix — OPTIONAL Pi assistant pattern.
#
# Not imported by the default profiles: Pi is optional, and machine
# assistant settings must never be shipped by this repo
# (docs/assistant-tooling.md). To enable Pi in a Home Manager profile,
# import this module and set:
#
#   nixdev.assistant.enable = true;
#   nixdev.assistant.package = pkgsUnstable.pi-coding-agent;
#
# (or any pkgs attribute that provides the `pi` binary). The module only
# installs the binary — there is NO provider/model configuration here;
# Pi's runtime state stays in ~/.pi/agent (0600), and the local
# llama.cpp fallback is configured at runtime with `pi login llama.cpp`.
#
# Claude Code is intentionally NOT packaged at all (docs/claude-code.md),
# and Firstmate is a separate private repository (docs/assistant-tooling.md).
{ config, lib, ... }:

let
  cfg = config.nixdev.assistant;
in
{
  options.nixdev.assistant = {
    enable = lib.mkEnableOption "the Pi assistant (optional; no provider/model configured)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        Package providing the `pi` binary (e.g. `pkgsUnstable.pi-coding-agent`).
        Must be set when `nixdev.assistant.enable` is true.
      '';
    };
  };

  config = {
    home.packages = lib.optional (cfg.enable && cfg.package != null) cfg.package;

    assertions = [
      {
        assertion = !cfg.enable || cfg.package != null;
        message = "nixdev.assistant.enable requires nixdev.assistant.package to be set.";
      }
    ];
  };
}