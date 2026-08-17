# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
- The README is the entry point; this file is for what the README does not already say.

## What this repository is

- Shared, **terminal-only** development environment for two machines: the MetaCube NixOS desktop (`devShells.desktop`, GitHub via `gh`) and the Arch WSL2 work laptop (`devShells.laptop` = `default`, company GitLab via `glab`), plus an optional `devShells.assistant` (Pi, no provider/model configured).
- **Not** the nixos-config repository: no NixOS modules, hosts, desktop session, or system services belong here. Do not copy desktop GUI/desktop config into this repo.
- No secrets, credentials, API keys, or machine-specific assistant settings are ever accepted — this is enforced by `scripts/check.sh` (credential-shaped string scan over tracked files).

## Key commands

- Enter a shell: `nix develop` (laptop) / `nix develop .#desktop` / `nix develop .#assistant`.
- Validate everything: `scripts/check.sh` — static checks (layout, bash -n, shellcheck, YAML/JSON parse, no-secrets scan) + `nix flake check` + non-activating builds of all devShell outputs. **This is the authoritative prereq for any PR; CI is intentionally absent.**
- Update inputs: `nix flake update` (or per-input); rollback is a flake.lock revert (docs/updates.md). Dependabot opens weekly nix-lane PRs.

## Where decisions live (docs are authoritative)

- WSL2/Nix-on-laptop setup: `docs/wsl2-prerequisites.md`
- Files on the WSL side, never `/mnt/c`: `docs/project-placement.md`
- Claude Code is native-installed only, never Nix-pinned: `docs/claude-code.md`
- GitHub-read-only vs company-GitLab on the laptop: `docs/git-workflow.md`
- Pi is optional with a local llama.cpp fallback; firstmate stays a separate repo with private per-machine harness choice: `docs/assistant-tooling.md`
- Phase 2 standalone Home Manager profile (parameterized username/home dir, portable modules only): `docs/home-manager.md`

## Sharp edges

- `flake.lock` must always be committed with `flake.nix` changes; `nix flake lock` refuses to run until the flake files are `git add`-ed.
- The flake's `nixConfig.experimental-features` is ignored on untrusted trees — the laptop setup doc therefore recommends the one-time `~/.config/nix/nix.conf` edit (`experimental-features = nix-command flakes`).
- Package lists live only in `flake.nix` (mkShell routes `packages` to `nativeBuildInputs`); Phase 2 HM must import the same lists, not duplicate them.
- Role split is defined by the flake's package lists — verify with the derivation's inputs (e.g. `nix derivation show`), not with `command -v` inside a shell on the desktop, whose host PATH contains both machines' tools.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.