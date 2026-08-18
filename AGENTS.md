# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
- The README is the entry point; this file is for what the README does not already say.

## What this repository is

- Shared, **terminal-only** development environment for two machines: the MetaCube NixOS desktop (`devShells.desktop`, GitHub via `gh`) and the Arch WSL2 work laptop (`devShells.laptop` = `default`, company GitLab via `glab`), plus an optional `devShells.assistant` (Pi, no provider/model configured) and an optional `devShells.firstmate` + opt-in Firstmate toolchain profile (`home/profiles/firstmate.nix`, `homeManagerModules.firstmate`/`.firstmateTools`, `lib/firstmate.nix`, `firstmate/node-tools/` — docs/firstmate.md). Since Phase 2 the same repo also exports portable Home Manager modules/profiles (`home/`, `lib.mkStandalone`) with the identical role split.
- **Not** the nixos-config repository: no NixOS modules, hosts, desktop session, or system services belong here. Do not copy desktop GUI/desktop config into this repo.
- No secrets, credentials, API keys, or machine-specific assistant settings are ever accepted — this is enforced by `scripts/check.sh` (credential-shaped string scan over tracked files).

## Key commands

- Enter a shell: `nix develop` (laptop) / `nix develop .#desktop` / `nix develop .#assistant` / `nix develop .#firstmate` (opt-in toolchain).
- Standalone Home Manager activation is documented in `docs/home-manager.md` (thin personal wrapper flake + `lib.mkStandalone`; generation-based rollback). It is never run from this repo's own validation.
- Validate everything: `scripts/check.sh` — static checks (layout, bash -n, shellcheck, YAML/JSON parse, no-secrets scan) + `nix flake check` + non-activating builds of all devShell outputs and the Home Manager role profiles including the opt-in firstmate variants (built via `lib.mkStandalone` with a throwaway test user). **This is the authoritative prereq for any PR; CI is intentionally absent.**
- Update inputs: `nix flake update` (or per-input); rollback is a flake.lock revert (docs/updates.md). Dependabot opens weekly nix-lane PRs (stable lane = nixpkgs + home-manager) plus an npm lane for the pinned Firstmate axi CLIs (`firstmate/node-tools`).

## Where decisions live (docs are authoritative)

- WSL2/Nix-on-laptop setup: `docs/wsl2-prerequisites.md`
- Files on the WSL side, never `/mnt/c`: `docs/project-placement.md`
- Claude Code is native-installed only, never Nix-pinned: `docs/claude-code.md`
- GitHub-read-only vs company-GitLab on the laptop: `docs/git-workflow.md`
- Pi is optional with a local llama.cpp fallback; firstmate stays a separate repo with private per-machine harness choice: `docs/assistant-tooling.md`
- Opt-in Firstmate toolchain profile (tools only, pins, activation on both machines): `docs/firstmate.md`
- Phase 2 Home Manager modules/profiles (parameterized, rollback via generations, nixos-config import surface): `docs/home-manager.md`
- Home Manager is pinned to `release-26.05` with nixpkgs following this repo's pin; HM modules are plain HM modules (importable standalone and from NixOS-side HM) — never NixOS system modules.

## Sharp edges

- `flake.lock` must always be committed with `flake.nix` changes; `nix flake lock` refuses to run until the flake files are `git add`-ed.
- The flake's `nixConfig.experimental-features` is ignored on untrusted trees — the laptop setup doc therefore recommends the one-time `~/.config/nix/nix.conf` edit (`experimental-features = nix-command flakes`).
- Package lists live only in `lib/package-lists.nix` (devShells and Home Manager profiles import the same functions — never duplicate them in a module). The devShell routes `packages` to `nativeBuildInputs`. The optional Firstmate toolchain is the one deliberate exception to the package-list location: it needs the npm lockfile root and pinned external binaries, so it lives in `lib/firstmate.nix` (single source for both the devShell and the HM module — never copy its tools list into a module).
- Role split is defined by the package lists and the role profiles — verify with the derivation's inputs (e.g. `nix derivation show`) or `config.home.packages`, not with `command -v` inside a shell on the desktop, whose host PATH contains both machines' tools.
- Flake evaluation is pure: `builtins.getEnv` returns "" in pure mode, so the flake cannot read `$USER`/`$HOME`. Parameterization is therefore a documented wrapper (`lib.mkStandalone`) and validation builds use `--impure` only to evaluate that factory with a throwaway test user.
- `home-manager` CLI and configs must be the same release; the repo re-exports the pinned CLI as `packages.<system>.home-manager` for that reason. Home Manager git config lives in `~/.config/git/config` by design, so the local `~/.gitconfig` identity is never overwritten.
- Firstmate tool pins: axi CLIs in `firstmate/node-tools/package.json` (+ lockfile) — bumped by the Dependabot npm lane for `/firstmate/node-tools`, then validated by `scripts/check.sh`; no-mistakes/herdr as SRI-pinned release assets in `lib/firstmate.nix` and treehouse as a tag-pinned flake input (`flake.nix`) move by deliberate edit/ref bump (docs/updates.md). `scripts/check.sh` builds the firstmate devShell and both firstmate profile variants (with/without the herdr backend) on every run.
- Treehouse export contract (docs/firstmate.md): the single treehouse pin is exported as `packages.${system}.treehouse`; `lib.mkStandalone` wires it into `homeManagerModules.firstmateTools` internally, while external NixOS Home Manager consumers (nixos-config) must pass it via explicit `extraSpecialArgs` using only this flake's public outputs — never a second treehouse flake input. `scripts/check.sh` regression-builds that external-consumer call shape (tmux ± herdr) offline. Package ownership lives here; per-machine Treehouse capacity/workspace state and Firstmate home/runtime settings are consumer-owned.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.