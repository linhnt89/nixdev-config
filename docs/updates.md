# Updates and rollback

This adopts the desktop configuration's update policy, adapted to a
repo that ships devShells *and* Home Manager profiles (Phase 2,
docs/home-manager.md). One nixpkgs pin covers both surfaces.

## Principles

- **Updates are deliberate, locally validated; CI stays optional.** Dependabot
  opens one targeted PR per lane, and `scripts/check.sh` is the authoritative
  validation gate. No CI is configured and none is required. Since the
  auto-merge helper (below) landed, eligible bot PRs may merge before anyone
  runs `scripts/check.sh`; required checks, if configured later, remain
  enforced by GitHub.
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
| Laptop standalone HM (companion lane) | local `path:` checkout + the wrapper's `flake.lock` | `scripts/update-home-manager.sh` — fast-forward the checkout, re-lock the wrapper input, build, opt-in `--switch`; rollback = wrapper lock backup + `home-manager rollback` (docs/home-manager.md) |
| Firstmate — treehouse | `treehouse` input (flake pinned at tag `v2.1.1`, its nixpkgs follows `nixpkgs-unstable`) | Dependabot individual PR (deliberate, not grouped) or `nix flake update treehouse`; docs/firstmate.md |
| Firstmate — axi CLIs | `firstmate/node-tools/package.json` + `package-lock.json` | Dependabot npm-lane PR for `firstmate/node-tools` (weekly); validated with `scripts/check.sh` |
| Firstmate — no-mistakes / herdr | pinned release assets in `lib/firstmate.nix` (URL + SRI) | Manual deliberate bump (version + URL + hash edit); not Dependabot-tracked |

The desktop PC has its own separate lane,
`nixos-config/scripts/update-nixdev-config.sh`, which updates the
nixdev-config flake input there; it is not part of this repository.

`nixpkgs-unstable` is excluded from the stable group on purpose: the Pi lane
moves only when an assistant-tooling update is actually wanted, not silently
with every stable bump. The same deliberate-lane policy applies to `treehouse`
(the Firstmate worktree provider) and to the URL/SRI-pinned release assets
(no-mistakes, herdr): those need a version+hash edit and are never auto-bumped
— mirroring how Firstmate's own installers pin release assets (docs/
firstmate.md). The pinned axi CLIs are the exception: they move via Dependabot's
npm lane for `firstmate/node-tools`, and every bump PR is validated with
`scripts/check.sh` (the Nix build consumes the regenerated lockfile) — and,
like all bot PRs, auto-merged by the helper below.

## Dependabot

`.github/dependabot.yml`: weekly nix updates **plus an npm lane** for
`firstmate/node-tools` (the pinned Firstmate axi CLIs).

### Auto-merge helper (the only workflow; not CI)

`.github/workflows/dependabot-automerge.yml` is this repository's **only**
workflow, and it is an admin helper, not CI: it requests **squash
auto-merge** for Dependabot version-update PRs — author exactly
`dependabot[bot]`, base = the default branch, repository
`linhnt89/nixdev-config` — via the `gh` CLI on the hosted runner. It never
checks out, executes, or evaluates PR code, never merges directly, and
never approves reviews.

One-time prerequisite: **allow auto-merge for the repository** (Settings →
General → Pull requests → "Allow auto-merge"). Until then the job fails on
every bot PR — that failure is the intended signal that the setting is
missing.

Consequence: with **no required checks**, eligible bot PRs — including the
deliberate nixpkgs-unstable and treehouse lanes — may **merge promptly**
after they open, without a human review or a local `scripts/check.sh` run.
Local validation stays authoritative for what it covers; to keep a PR or a
lane manual, disable auto-merge on the PR, close the PR, or configure a
required check later — required checks remain enforced by GitHub and block
the auto-merge until they pass. Branch protection stays authoritative.

Review checklist for PRs you review (or before merging non-bot PRs):

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

Only Dependabot opens PRs, and this single admin workflow is the only
workflow — no Renovate, no second bot, no scheduled jobs, no CI/build
workflows.

## Manual update

```bash
nix flake update            # bump all inputs to current branch heads
scripts/check.sh            # validate before committing the lock change
```

For the laptop's standalone Home Manager profile, the checkout and the
wrapper move through the companion lane instead (fast-forward + build,
activation opt-in):

```bash
scripts/update-home-manager.sh              # fast-forward + build, no activation
scripts/update-home-manager.sh --switch     # add opt-in activation
```

## Rollback

```bash
git log -- flake.lock                    # find the last good lock commit
git checkout <commit> -- flake.lock      # or `nix flake lock --revert`
scripts/check.sh
```

Because nothing here activates a system, "rollback" never touches a machine;
it is purely which pinned revisions the next `nix develop` uses.

For the laptop's standalone Home Manager profile, rollback is
**generation-based** once activated, plus the wrapper-pin backup the lane
saves on `--switch`:

```bash
home-manager rollback       # undo the last activation (docs/home-manager.md)
# and optionally restore the pre-update wrapper pin:
cp ~/.config/home-manager/flake.lock.pre-update.<ts> \
   ~/.config/home-manager/flake.lock
```