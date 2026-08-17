# Updates and rollback

This adopts the desktop configuration's update policy, adapted to a
repo that ships devShells *and* Home Manager profiles (Phase 2,
docs/home-manager.md). One nixpkgs pin covers both surfaces.

## Principles

- **Updates are deliberate, reviewed, locally validated.** Dependabot opens
  one targeted PR per lane; every PR must pass `scripts/check.sh` before
  merge. No CI is configured and none is required — local validation is the
  authoritative gate.
- **Never self-update Nix-managed tools.** Tools that come from these
  devShells or the Home Manager profiles are immutable in the Nix store;
  their versions change only through this repository's pins, never via
  `npm update`, `apt`, or a project's own auto-updater. Claude Code is
  the documented exception because it is deliberately **not** Nix-managed
  (docs/claude-code.md).
- **Rollback is a lock revert** for the devShells, and **generation-based**
  for the Home Manager profiles once activated (`home-manager rollback` /
  `home-manager generations` — docs/home-manager.md).

## Update lanes

| Lane | Pin | How it moves |
| --- | --- | --- |
| Stable shell + HM packages | `nixpkgs` + `home-manager` inputs (`nixos-26.05` / `release-26.05`, HM's nixpkgs follows ours) | Dependabot weekly nix PR (grouped) or `nix flake update nixpkgs home-manager` |
| Assistant lane (Pi) | `nixpkgs-unstable` input | Dependabot individual PR (deliberate, not grouped) or `nix flake update nixpkgs-unstable` |

`nixpkgs-unstable` is excluded from the stable group on purpose: the Pi lane
moves only when an assistant-tooling update is actually wanted, not silently
with every stable bump.

## Dependabot

`.github/dependabot.yml`: weekly nix updates. Review checklist for every PR:

1. `scripts/check.sh` passes locally (static checks + `nix flake check` +
   non-activating builds of the devShells).
2. The diff touches only `flake.lock` (and `flake.nix` only for
   deliberate ref rewrites).
3. Unstable-lane PRs: confirm the Pi package change is wanted.

Only Dependabot runs — no Renovate, no second bot, no scheduled jobs, no CI
workflows.

## Manual update

```bash
nix flake update            # bump all inputs to current branch heads
scripts/check.sh            # validate before committing the lock change
```

## Rollback

```bash
git log -- flake.lock                    # find the last good lock commit
git checkout <commit> -- flake.lock      # or `nix flake lock --revert`
scripts/check.sh
```

Because nothing here activates a system, "rollback" never touches a machine;
it is purely which pinned revisions the next `nix develop` uses.