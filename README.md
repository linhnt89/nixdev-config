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

## Quick start

```bash
# Laptop (Arch WSL2, Nix installed per docs/wsl2-prerequisites.md)
nix develop                # -> laptop role shell (glab)

# Desktop (MetaCube)
nix develop .#desktop      # -> desktop role shell (gh)

# Either machine, optional assistant shell (Pi, no provider/model configured)
nix develop .#assistant

# Use direnv instead: add `use flake` to a project's .envrc after installing
# nix-direnv (both shell roles ship direnv + nix-direnv).
```

## What is inside

```
flake.nix                  # two nixpkgs inputs (stable + unstable Pi lane), role devShells
flake.lock                 # pinned revisions; Dependabot bumps weekly (docs/updates.md)
README.md                  # this file
AGENTS.md / CLAUDE.md      # agent memory for this repo (CLAUDE.md is a symlink)
.envrc                     # direnv/nix-direnv entry for this repo's own development
docs/
  wsl2-prerequisites.md    # Windows/WSL2 setup needed before this repo works on the laptop
  project-placement.md     # where to put checkouts/files: WSL filesystem, never /mnt/c
  claude-code.md           # native install/update boundary + no-secrets rule
  git-workflow.md          # GitHub-read-only vs company-GitLab workflows per role
  updates.md               # update lanes and rollback
  home-manager.md          # Phase 2: standalone, parameterized HM integration
  assistant-tooling.md     # Pi (optional, llama.cpp fallback) + firstmate separation
scripts/check.sh           # local validation gate (static checks + flake check + shell builds)
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
- **Reproducible and mine to update.** `flake.lock` pins everything;
  updates move via Dependabot PRs or `nix flake update`, validated by
  `scripts/check.sh` before merge. Rollback is a lock revert.
- **Local validation is the authoritative gate.** `scripts/check.sh`
  (static checks + `nix flake check` + non-activating builds of every
  devShell) must pass before any PR is merged. CI is not configured and
  not required. Direct PRs; merge approval stays with firstmate/captain.
- **This is not the nixos-config repository.** No NixOS modules, hosts,
  desktop session config, or SSH-server setup from the MetaCube config
  belongs here. The desktop consumes this project additively.

## Phase status

- **Phase 1 (this repository today):** shared flake + role devShells +
  docs + local validation. Claude Code and Pi are *not* Nix-managed;
  see docs/claude-code.md and docs/assistant-tooling.md.
- **Phase 2 (documented, not implemented):** standalone Home Manager
  profile for the laptop (`homeConfigurations."<user>@laptop"`,
  parameterized), wired to the same role split — see docs/home-manager.md.

## Workflow

1. Branch, change, commit.
2. Run `scripts/check.sh` locally — it must pass.
3. Open a direct PR with a summary; merge approval is the captain's/
   firstmate's call. Remote CI is intentionally absent.