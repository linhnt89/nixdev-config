# Home Manager integration (Phase 2, implemented)

Phase 1 shipped devShells only. Phase 2 adds **portable, parameterized
Home Manager modules and role profiles** to the same flake: a shared
terminal environment that can be activated standalone on the Arch WSL2
laptop *and* consumed later by the MetaCube NixOS configuration through
Home Manager embedded in NixOS (a follow-up nixos-config PR).

Everything here is portable: modules and profiles importable from
standalone Home Manager on any Linux machine, with username, home
directory, and role as parameters — never hard-coded `linhnt` paths.

## devShell vs Home Manager activation

| | `nix develop` (devShell) | Home Manager profile |
| --- | --- | --- |
| What it is | A temporary shell environment | A persistent set of dotfiles + user packages |
| Where tools live | The Nix store; `PATH` only while inside the shell | `~/.config/…`, `~/.zshrc`, profile generations |
| Persistence | Nothing changes in the home directory | `~/.config`, shell rc files, and more are managed symlinks |
| Clone / update | Magic, disposable, never self-updated | Generation-based, reviewable, rollback via generations |

The devShells (`nix develop` / direnv) are still the *default* way to get
the tools on any machine. The Home Manager profile is the *persistent*
way: it installs the same package set and additionally manages the
portable dotfiles (shell, starship, fzf, bat, eza, git/delta structure,
direnv/nix-direnv). You can use both — the devShell for scratch work,
the profile for daily use — and neither conflicts with the other.

Package drift between the two is impossible by construction: both read
the same package lists from `lib/package-lists.nix` against the same
`nixpkgs` pin (the devShells via `packages`/`nativeBuildInputs`, the
profiles via `home.packages` and `programs.*` package options).

## Role outputs

| Output | Role | Git hosting CLI | Who consumes it |
| --- | --- | --- | --- |
| `homeManagerModules.laptop` / `lib.mkStandalone { role = "laptop" }` | laptop / work | `glab` (company GitLab) | standalone Arch WSL2 |
| `homeManagerModules.desktop` / `lib.mkStandalone { role = "desktop" }` | desktop / personal | `gh` (GitHub) | later nixos-config PR, or any Linux box |
| `homeManagerModules.shell` / `.git` / `.dev` | common | — | imported by both roles, or individually by consumers |
| `homeManagerModules.assistant` | optional Pi | — | opt-in; no provider/model credentials |

The role split is preserved exactly: the laptop profile installs `glab`
and **never** `gh`; the desktop profile installs `gh` and **never**
`glab`. GitHub on the laptop stays read-only and on demand
(`nix shell nixpkgs#gh`, docs/git-workflow.md).

## Flake outputs

- `homeManagerModules.*` — reusable portable Home Manager modules
  (individual pieces or the complete role profiles).
- `lib.mkStandalone { username, homeDirectory, role ? "laptop", ... }` —
  the parameterized factory for standalone activation (below).
- `packages.<system>.home-manager` — the home-manager CLI, pinned to this
  repo's home-manager input (`nix run .#home-manager`).
- `devShells.*` — unchanged from Phase 1, now fed from the same package
  lists the profiles use.

## Standalone activation on the laptop (and any Linux box)

The repo itself never hard-codes a username or home directory — flake
evaluation is pure, so `$USER`/`$HOME` cannot be read inside the flake.
Instead, a **thin personal wrapper flake** supplies the parameters. The
repository ships a copy-paste template at
`home/standalone/flake.nix.template`; copy it to
`~/.config/home-manager/flake.nix` (the home-manager CLI auto-discovers
that path) and fill in the three parameters:

```nix
# ~/.config/home-manager/flake.nix  (personal, per-machine file)
# copy of home/standalone/flake.nix.template with parameters filled in
{
  inputs.nixdev-config.url = "path:/path/to/nixdev-config";

  outputs = { nixdev-config, ... }: {
    homeConfigurations.laptop = nixdev-config.lib.mkStandalone {
      username = "you";          # <- the actual WSL2 username
      homeDirectory = "/home/you"; # <- the actual home path
      role = "laptop";           # or "desktop" for the gh role
    };
  };
}
```

The attribute name is yours to choose — but match the command: the CLI
looks up `homeConfigurations.$USER` (or `$USER@$HOSTNAME`) when invoked
without a `--flake` argument, and `homeConfigurations.$NAME` when invoked
with `--flake .#$NAME`. The example above names it `laptop`, so use the
`--flake` form below; if you prefer zero-flag activation, name the
attribute after your user (e.g. `homeConfigurations.linhnt`).

Then, from a login shell in the WSL2 distro:

```bash
# activation is generation-based: `home-manager switch` or the
# activation package built from the same configuration.
cd ~/.config/home-manager
home-manager switch --flake .#laptop   # matches the attr name above
# plain `home-manager switch` also works when the attribute is named
# after $USER (e.g. `homeConfigurations.linhnt`) — the CLI auto-\
# discovers ~/.config/home-manager/flake.nix

# rollback / inspection (generation-based, like NixOS):
home-manager generations
home-manager rollback               # switch back to a previous generation
```

First run will download the pinned packages; activation is fully
tracked as Home Manager generations (`~/.local/state/home-manager`), so
`home-manager rollback` undoes the last switch. Nothing here requires
`sudo` or any system-level change.

### WSL2 prerequisites (documented and tested on the laptop setup)

- Home Manager's user services and `environment.d` integration rely on
  **systemd running in the distro** — already required by
  `docs/wsl2-prerequisites.md` (`[boot] systemd=true` in `/etc/wsl.conf`,
  verified with `systemctl is-system-running`). Without systemd, Home
  Manager warns and its user units silently degrade; the profile itself
  defines no services, so nothing else about it requires system changes.
- Nix must be installed with flakes enabled (nix.conf
  `experimental-features`), per the same doc.
- Keep the checkout and `~/.config/home-manager/flake.nix` on the Linux
  side, never `/mnt/c` (docs/project-placement.md).
- The profile configures zsh but does **not** change the login shell —
  swapping the login shell needs `/etc/shells` on the system side, which
  stays out of scope (bash integration is enabled so the profile works
  either way; `zsh` starts wherever you invoke it).

## Updating the laptop's standalone profile (companion lane)

The laptop's standalone setup consumes the local nixdev-config checkout
directly (`path:` input, above), so "updating Home Manager" means:
fast-forward that checkout, point the wrapper's `nixdev-config` input at the
new revision, build the profile, and — only on request — activate it. That
is exactly what the portable companion script does:

```bash
scripts/update-home-manager.sh              # preflight + fast-forward + build (NO activation)
scripts/update-home-manager.sh --dry-run    # read-only preflight, prints the exact commands
scripts/update-home-manager.sh --switch     # ...and activate (opt-in; --apply is an alias)
```

It is runnable from either side of the setup:

- from the checkout: `cd ~/firstmate/projects/nixdev-config && scripts/update-home-manager.sh`
- from the wrapper:  `~/firstmate/projects/nixdev-config/scripts/update-home-manager.sh`

Defaults: checkout `$HOME/firstmate/projects/nixdev-config`, wrapper
`$HOME/.config/home-manager`; both are overridable with
`--checkout DIR` / `--wrapper DIR`, plus `--profile NAME` (or
`--flake DIR#NAME`) to select the `homeConfigurations.<NAME>` attribute —
auto-detected when the wrapper defines exactly one. `--remote NAME` /
`--branch NAME` disambiguate unusual remotes/branches. `--help` documents
everything.

What the script guarantees:

- It refuses dirty, detached, conflicted, wrong-branch, diverged
  (non-fast-forwardable), multi-remote, wrapper/checkout-mismatched, and
  ambiguous-profile states. Nothing is stashed, reset, cleaned, rebased, or
  merged; the checkout is only ever fast-forwarded from its configured
  remote.
- The wrapper is inspected read-only. The single wrapper mutation is
  `nix flake lock --update-input nixdev-config` — regenerating the
  generated `flake.lock` so it records the new checkout revision (the point
  of an update). `flake.nix` and every private file stay byte-identical.
  On `--switch` a timestamped `flake.lock.pre-update.<ts>` backup is kept
  for pinning back.
- The build uses the repo's pinned home-manager CLI
  (`nix run <checkout>#home-manager -- build --flake <wrapper>#<name>`);
  `nixos-rebuild`, system services, and desktop activation are never run.
- Fetch/authentication and build failures stop before any activation and
  leave both the checkout and the wrapper fully inspectable.

Rollback is generation-based as always — the script prints the exact
commands after a successful switch:

```bash
home-manager generations      # inspect
home-manager rollback         # undo the last switch
```

To additionally pin the wrapper back to the pre-update nixdev-config
revision, restore the saved `flake.lock.pre-update.<ts>` backup and switch
again. The checkout keeps every old commit (fast-forward only adds
history), and the lane is covered by offline regression tests
(`tests/run-tests.sh`, run by `scripts/check.sh`).

This is the **laptop companion lane**. The PC consumes this repo as a flake
input; its update lane is the separate
`nixos-config/scripts/update-nixdev-config.sh` script in the nixos-config
repository, using the same path convention
(`$HOME/firstmate/projects/nixos-config`).

## How nixos-config will consume this (later PR, not this repo)

A follow-up PR in the **nixos-config** repository will import these
modules instead of duplicating them. That PR is out of scope for this
repository and must not be started here; this repo only guarantees the
import surface:

```nix
# inside nixos-config (later), e.g. per-user:
home-manager.users.${username} = {
  imports = [
    nixdev-config.homeManagerModules.desktop   # gh role profile for MetaCube
    # - or - pick pieces: .shell .git .dev .assistant
  ];
  home.username = username;            # parameters come from NixOS here
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "26.05";         # may override the profile default
};
```

nixos-config keeps everything that is **not** portable: NixOS modules,
system services, users/groups, boot, hardware, networking, the desktop
session, and the personal identity/SSH block that lives in the desktop's
own configuration. This repo contributes only the portable terminal
layer, so `scripts/check.sh` here can validate it without any NixOS
evaluation anywhere.

## Boundaries (unchanged from Phase 1)

- **No secrets in Nix, ever.** No git identity, no SSH host blocks, no
  remotes, no credentials, no API keys, no OAuth state, no
  machine-specific assistant settings. The git module creates only
  *structure* (`~/.config/git/config`: default branch, delta pager,
  push.autoSetupRemote); identity stays in each machine's local
  `~/.gitconfig` / `~/.ssh` / glab / gh / `~/.pi` stores.
  `scripts/check.sh` scans for credential-shaped strings on every run.
- **No GUI, no system services, no NixOS modules in this repo.** The
  portable profile is terminal-only.
- **Rollback is generation-based** once activated (`home-manager
  rollback`), and the repo's own lock is always revertible
  (docs/updates.md). Nothing here ever runs `nixos-rebuild` or touches
  system state.
- **Activation is always opt-in.** Default usage remains `nix develop`;
  the Home Manager profile is something you explicitly set up and
  switch to.