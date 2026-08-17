# home/modules/dev.nix — portable development tooling configuration.
#
# Development *packages* (nodejs, just, shellcheck, lazygit, CLI utils)
# come from the shared common set via the shell module; this module only
# configures the project-environment layer: direnv + nix-direnv with
# caching, wired into the shells. No credentials, no machine-specific
# settings.
{ ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # load-file caching; same as the devShells
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}