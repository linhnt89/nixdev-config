# home/modules/git.nix — git structure only, never identity.
#
# Writes the shared git/delta *structure* to ~/.config/git/config via
# home-manager. Deliberately contains NO personal data: no user.name /
# user.email, no SSH host blocks, no remotes, no signing keys, no
# credentials. Those stay in the machine's local files (~/.gitconfig,
# ~/.ssh, glab/gh auth stores) per docs/git-workflow.md; the no-secrets
# scan in scripts/check.sh enforces the same boundary repo-wide.
{ lib, pkgs, ... }:
{
  programs.git = {
    enable = true;
    # The shared package list ships gitFull; pin the profile to the exact
    # same binary so the devShell and the profile cannot diverge.
    package = pkgs.gitFull;

    settings = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      # Personal workflow choices (pull strategy, signing, aliases) are
      # deliberately left out — they belong in the local ~/.gitconfig.
    };
  };

  # delta as the diff pager for git (programs.git.delta.* was renamed to
  # the standalone programs.delta module upstream).
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };
}