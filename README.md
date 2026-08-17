# nixdev-config

Shared, **terminal-only** development environment for the two machines that
collaborate on personal projects:

| Role | Machine | Git hosting CLI | Nix |
| --- | --- | --- | --- |
| `laptop` (default) | Windows 11 + Arch WSL2 work laptop | `glab` (company GitLab) | freshly installed inside the Arch distro |
| `desktop` | MetaCube NixOS PC | `gh` (GitHub) | already present (this repo is additive) |

Both machines consume the **same flake** from this repository; the role
split changes only which Git hosting CLI is on `PATH` and which workflow is
the documented default. Nothing in this repository touches desktop
configuration, system services, or credentials.

Since Phase 2 the flake also ships **portable Home Manager modules and
role profiles** (same package lists, same role split) for persistent,
generation-based activation — the laptop's daily environment once set up.
The quick start below covers the ephemeral shells; docs/home-manager.md
covers the Home Manager profile and its activation.

## Quick start

```bash
# Laptop (Arch WSL2, Nix installed per docs/wsl2-prerequisites.md)
nix develop                # -> laptop role shell (glab)

# Desktop (MetaCube)
nix develop .#desktop      # -> desktop role shell (gh)

# Either machine, optional assistant shell (Pi, no provider/model configured)
nix develop .#assistant

# Either machine, optional Firstmate toolchain (pinned; see docs/firstmate.md)
nix develop .#firstmate

# Use direnv instead: add `use flake` to a project's .envrc after installing
# nix-direnv (both shell roles ship direnv + nix-direnv).
```

For the persistent Home Manager profile (shell/starship/fzf/git-delta
dotfiles plus the same package set, activated and rolled back by
`home-manager switch` / `home-manager rollback`), see
[docs/home-manager.md](docs/home-manager.md). For the **opt-in Firstmate
toolchain profile** (the binaries Firstmate's bootstrap needs, for a machine
that runs Firstmate), see [docs/firstmate.md](docs/firstmate.md) — tools
only; the Firstmate machine clone origin is
<https://github.com/linhnt89/firstmate> (upstream:
<https://github.com/kunchenguid/firstmate>) and its per-machine
`data/`/`state/`/`config/`/`projects/` stay in the machine's private home.

## What is inside

```
flake.nix                  # inputs (nixpkgs, nixpkgs-unstable, home-manager),
                           # role devShells, homeManagerModules, lib.mkStandalone
flake.lock                 # pinned revisions; Dependabot bumps weekly (docs/updates.md)
lib/package-lists.nix      # single source of truth for the package lists (Phase 2)
                           # consumed by both devShells and Home Manager profiles
lib/firstmate.nix          # shared Firstmate toolchain builders (Phase 3, docs/firstmate.md)
firstmate/node-tools/      # pinned Firstmate axi CLIs (package.json + package-lock.json)
home/                      # portable Home Manager modules + role profiles (Phase 2)
  modules/                 #   shell, git (structure only), dev, assistant (opt-in),
                           #   firstmateTools (opt-in Firstmate toolchain)
  profiles/                #   laptop (glab), desktop (gh), firstmate (opt-in) profiles
  standalone/              #   wrapper flake template for standalone activation
README.md                  # this file
AGENTS.md / CLAUDE.md      # agent memory for this repo (CLAUDE.md is a symlink)
.envrc                     # direnv/nix-direnv entry for this repo's own development
docs/
  wsl2-prerequisites.md    # Windows/WSL2 setup needed before this repo works on the laptop
  project-placement.md     # where to put checkouts/files: WSL filesystem, never /mnt/c
  claude-code.md           # native install/update boundary + no-secrets rule
  git-workflow.md          # GitHub-read-only vs company-GitLab workflows per role
  updates.md               # update lanes and rollback
  home-manager.md          # Phase 2: portable, parameterized HM modules/profiles (live)
  assistant-tooling.md     # Pi (optional, llama.cpp fallback) + firstmate separation
  firstmate.md             # Phase 3: opt-in Firstmate toolchain (tools only, pinned)
scripts/check.sh           # local validation gate (static checks + flake check + builds)
.github/dependabot.yml     # nix update lanes (weekly), no CI
```

## Project principles

- **Terminal-only.** No GUI, compositor, audio, Bluetooth, portals,
  hardware, boot, firewall, or system-service configuration — nowhere in
  this repository.
- **No secrets in Nix, ever.** Credentials, API keys, OAuth state, and
  machine-specific assistant settings live in runtime-owned files
  (`~/.ssh/`, `~/.claude/`, `~/.pi/agent/`, `~/.gitconfig`). Nothing
  credential-shaped is accepted here; `scripts/check.sh` greps for it.
- **Clean role split.** The desktop gets `gh`; the laptop gets `glab`. The
  shared base environment never installs the same Git hosting CLI for both
  roles. GitHub on the laptop is read-only (public sources), on demand via
  `nix shell nixpkgs#gh` — company GitLab is the laptop's push/pull home.
  The opt-in Firstmate profile is the documented exception: importing it
  adds `gh` because Firstmate requires it (docs/firstmate.md) — it never
  alters the default roles.
- **Reproducible and mine to update.** `flake.lock` pins everything;
  updates move via Dependabot PRs or `nix flake update`, validated by
  `scripts/check.sh` before merge. Rollback is a lock revert.
- **Local validation is the authoritative gate.** `scripts/check.sh`
  (static checks + `nix flake check` + non-activating builds of every
  devShell and both Home Manager role profiles) must pass before any PR
  is merged. CI is not configured and not required. Direct PRs; merge
  approval stays with firstmate/captain.
- **`nix develop` is ephemeral; the Home Manager profile is persistent.**
  Both consume the identical package lists (`lib/package-lists.nix`), so
they cannot drift. The profile activation is generation-based with
`home-manager rollback` (docs/home-manager.md).
- **This is not the nixos-config repository.** No NixOS modules, hosts,
  desktop session config, or SSH-server setup from the MetaCube config
  belongs here. The desktop consumes this project additively — the
  exported `homeManagerModules` are the future integration point for a
  nixos-config PR (docs/home-manager.md).

## Phase status

- **Phase 1 (bootstrap):** shared flake + role devShells + docs + local
  validation. Claude Code and Pi are *not* Nix-managed; see
  docs/claude-code.md and docs/assistant-tooling.md.
- **Phase 2 (this change, implemented):** portable, parameterized Home
  Manager modules and role profiles (`home/`, `lib/package-lists.nix`,
  `lib.mkStandalone`, pinned home-manager input). Standalone activation
  on the laptop, and mandatory import surface for the desktop's
  nixos-config integration — see docs/home-manager.md.
- **Phase 3 (this change, implemented):** the opt-in Firstmate toolchain
  (Home Manager module/profile + `devShells.firstmate`), pinned and
  validated — see docs/firstmate.md.

## Workflow

1. Branch, change, commit.
2. Run `scripts/check.sh` locally — it must pass.
3. Open a direct PR with a summary; merge approval is the captain's/
   firstmate's call. Remote CI is intentionally absent.