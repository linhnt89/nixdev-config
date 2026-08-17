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
| Firstmate — treehouse | `treehouse` input (flake pinned at tag `v2.1.1`, its nixpkgs follows `nixpkgs-unstable`) | Dependabot individual PR (deliberate, not grouped) or `nix flake update treehouse`; docs/firstmate.md |
| Firstmate — axi CLIs | `firstmate/node-tools/package.json` + `package-lock.json` | Dependabot npm-lane PR for `firstmate/node-tools` (weekly); must pass `scripts/check.sh` |
| Firstmate — no-mistakes / herdr | pinned release assets in `lib/firstmate.nix` (URL + SRI) | Manual deliberate bump (version + URL + hash edit); not Dependabot-tracked |

`nixpkgs-unstable` is excluded from the stable group on purpose: the Pi lane
moves only when an assistant-tooling update is actually wanted, not silently
with every stable bump. The same deliberate-lane policy applies to `treehouse`
(the Firstmate worktree provider) and to the URL/SRI-pinned release assets
(no-mistakes, herdr): those need a version+hash edit and are never auto-bumped
— mirroring how Firstmate's own installers pin release assets (docs/
firstmate.md). The pinned axi CLIs are the exception: they move via Dependabot's
npm lane for `firstmate/node-tools`, and every bump PR must clear
`scripts/check.sh` (the Nix build consumes the regenerated lockfile).

## Dependabot

`.github/dependabot.yml`: weekly nix updates **plus an npm lane** for
`firstmate/node-tools` (the pinned Firstmate axi CLIs). Review checklist for
every PR:

1. `scripts/check.sh` passes locally (static checks + `nix flake check` +
   non-activating builds of the devShells).
2. Nix-lane PRs: the diff touches only `flake.lock` (and `flake.nix` only
   for deliberate ref rewrites).
3. Unstable-lane PRs: confirm the Pi package change is wanted.
4. treehouse-lane PRs: confirm the Firstmate worktree-provider version
   change is wanted and the new version still clears the Firstmate bootstrap
   floors (docs/firstmate.md).
5. npm-lane PRs: confirm the axi-CLI version updates `package.json` **and**
   `package-lock.json`, the new versions still clear the Firstmate bootstrap
   floors (gh-axi ≥ 0.1.29, lavish-axi ≥ 0.1.46, see bin/fm-bootstrap.sh),
   and `scripts/check.sh` builds the firstmate devShell/profile with them.

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