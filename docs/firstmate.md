# Firstmate toolchain profile (opt-in)

Firstmate is the autonomous worker agent that manages this repository's
sibling projects. Its **source is public**: the machine clone origin is
<https://github.com/linhnt89/firstmate> (a fork), whose upstream is
<https://github.com/kunchenguid/firstmate>. Each machine keeps a clone
("the Firstmate home", on the MetaCube desktop `/home/linhnt/firstmate`)
whose tracked files come from that fork and whose gitignored `data/`,
`state/`, `config/`, `projects/` directories are **private per-machine
content** (auth, harness choice, project clones, tokens). **None of that
lives in nixdev-config.** This flake only offers an optional, portable
**toolchain**: the binaries Firstmate's own bootstrap
(`bin/fm-bootstrap.sh`) requires.

This document covers what is installed, how to enable it on each machine, and
the update/credential boundaries. It is the counterpart of
[assistant-tooling.md](assistant-tooling.md) (Pi / Claude Code / Firstmate
boundaries) and follows the same rules as the other Home Manager profiles
([home-manager.md](home-manager.md)).

## Optional, opt-in, and never a default

- The default `laptop` profile installs `glab` and **never** `gh`; the default
  `desktop` profile installs `gh` and **never** `glab`. Importing the
  Firstmate profile changes neither of those defaults — it is an explicit,
  per-machine choice.
- Importing the Firstmate profile **does** install `gh`, because Firstmate
  currently requires `gh` (with GitHub auth) on every home. That is the
  documented exception to the role split, and it is why the profile is
  opt-in: a laptop that enables Firstmate deliberately accepts a `gh` binary
  alongside its `glab`.
- Nothing is installed by `nix develop` unless you run it; no Home Manager
  profile imports `homeManagerModules.firstmate` unless you add it.

## What gets installed

The verified **default/reference workflow is the tmux backend** (the backend
Firstmate resolves when nothing else is configured). The profile provides its
full toolchain:

| Tool | Version | Source / pin |
| --- | --- | --- |
| `node` | repo's `pkgs.nodejs` (node 24.x) | shared with the common package set — never a second Node |
| `git` | `pkgs.gitFull` | nixpkgs (shared common set) |
| `tmux` | nixpkgs (3.6.x) | tmux backend session CLI |
| `lsof` | nixpkgs | process inspection for Firstmate's operational safety checks |
| `jq` | nixpkgs (1.8.x) | also in the common set; required by the JSON-emitting backend adapters |
| `gh` | nixpkgs (2.97.x) | universal Firstmate requirement (the opt-in role-split exception) |
| `gh-axi` | **0.1.30** | npm, pinned in `firstmate/node-tools/package.json` |
| `chrome-devtools-axi` | **0.1.29** | npm, pinned in `firstmate/node-tools/package.json` |
| `lavish-axi` | **0.1.50** | npm, pinned in `firstmate/node-tools/package.json` |
| `tasks-axi` | **0.2.4** | npm, pinned in `firstmate/node-tools/package.json` |
| `quota-axi` | **0.1.21** | npm, pinned in `firstmate/node-tools/package.json` |
| `no-mistakes` | **1.46.0** | pinned release asset (SRI in `lib/firstmate.nix`) |
| `treehouse` | **2.1.1** | upstream flake pinned at tag `v2.1.1` (flake.lock) |
| `herdr` | **0.8.0** | pinned release asset — **opt-in only** (`nixdev.firstmate.enableHerdr`) |
| `crew-watch` | **0.1.1** | pinned source build (git tag `v0.1.1` commit + source/Cargo hashes in `lib/firstmate.nix`) — read-only diagnostic sidecar |

The five axi CLIs are installed from the committed lockfile
`firstmate/node-tools/package-lock.json` via nixpkgs' `importNpmLock`
(`buildNodeModules`), then wrapped with their `node_modules/.bin` and `node`
on `PATH` so they can exec each other. `gh-axi`/`lavish-axi` are installed
with their pinned versions and `setup hooks` is not needed — the wrappers
already point at the store's node_modules.

`treehouse` is built from the upstream flake (Go source) rather than the raw
release archive on purpose: the archived binary is glibc-dynamic and does not
run on the MetaCube NixOS desktop without nix-ld, while the Nix build is
patched for NixOS and runs on both machines. `no-mistakes` and `herdr` are
statically linked release binaries and run as-is on both machines.

All versions chosen clear the current Firstmate bootstrap floors
(`fm-bootstrap.sh`: gh-axi ≥ 0.1.29, lavish-axi ≥ 0.1.46, no-mistakes ≥
1.31.2) and match the versions already running on the desktop's nixos-config
integration where one exists.

### Optional Herdr backend

Firstmate's default backend is tmux. The experimental Herdr backend is a
per-machine choice (`config/backend` in the Firstmate home). If a machine
runs Herdr instead of tmux, its toolchain additionally needs the pinned
`herdr` binary — enable it explicitly in the profile:

```nix
nixdev.firstmate.enableHerdr = true;  # adds pinned herdr 0.8.0
```

This repository installs the **binary only**. It never starts, stops,
restarts, or drives any Herdr session or lifecycle — Firstmate does that via
its own bootstrap and backend scripts. Without this option the tmux backend
(already installed) remains the reference workflow.

### crew-watch — optional read-only human diagnostic sidecar

`crew-watch` is a **read-only terminal monitor** for firstmate fleets
(upstream <https://github.com/ppetermann/crew-watch>, MIT): the top half is
an htop-style system overview, the bottom half one row per running agent
session with subtree-aggregated CPU/MEM, model, elapsed, and `TASK`/`STATE`
columns read from a firstmate home. It is installed as a plain binary in the
toolchain — **nothing starts it, schedules it, or reads its output**: no
daemon, no systemd service, no auto-start hook, no wake/alert path. A human
runs it ad hoc in a terminal:

```bash
crew-watch --fm-home /home/<you>/firstmate            # live TUI, real home
crew-watch --fm-home /home/<you>/firstmate --once     # one-shot text dump
```

- **`--fm-home`** points at the machine's private Firstmate home (it reads
  `state/*.meta`, `state/*.status`, `state/*.busy-state` + `*.busy-gen`,
  `data/backlog.md`, `data/<task>/brief.md`). Without it the default is
  `$CREW_WATCH_FM_HOME`, then `~/agents/firstmate` — a deployment whose
  home lives elsewhere (e.g. the MetaCube desktop's `/home/linhnt/firstmate`)
  must pass `--fm-home` explicitly. Everything it reads is read-only and
  best-effort; it writes nothing back (the only file it may persist is its
  own `~/.config/crew-watch/config` quota-provider choice).
- **`--once`** collects two samples ~1s apart (so CPU% is a real delta) and
  dumps plain text to stdout, then exits 0 — for scripting/grepping. Its
  output is **not a versioned machine API**; treat it as text for humans.
- `--no-quota` skips the optional `quota-axi` fetch; `--interval <sec>` sets
  the TUI refresh (default 2s).

**Known limitations** (why it stays a sidecar, never a supervision input):

- **Stale STATE column.** `state/<id>.status` is an append-only event log and
  the TUI shows its last line, while firstmate's own
  `bin/fm-crew-state.sh` reconciles the log against the authoritative
  current state. A worker that silently resumed after a
  `needs-decision:`/`blocked:` tail can still render as open, and a worker
  whose process died without a `failed:` line can render as working until
  the next refresh. Firstmate's reconciliation is the source of truth; the
  TUI is a window, not a verdict.
- **Linux-only.** `/proc` is the process model by design.
- **Harness coverage.** Detection matches known agent runtimes
  (claude/opencode/codex/grok/kimi/muse/pi) by process basename; a
  `cursor`-backed worker gets no own row. It is not backend-aware (tmux/Herdr
  pane identity and busy signals are invisible).
- **Format drift.** The firstmate file formats it reads are an external
  contract owned by firstmate; it fails soft (one degraded signal per
  missing file) but can silently misread formats that drift. When this
  repo's pin moves, formats are re-verified (docs/updates.md).

**Boundary (unchanged by this addition):** the durable watcher, wake queue,
acknowledgements, current-state reconciliation, and backend lifecycle stay
firstmate-owned (`bin/fm-watch.sh`, `bin/fm-crew-state.sh`,
`bin/fm-busy-lib.sh`). `crew-watch` replaces none of them, and nothing reads
its output.

## Enabling it — laptop (standalone Home Manager)

Your `~/.config/home-manager/flake.nix` (copy of the template in
[`home/standalone/flake.nix.template`](../home/standalone/flake.nix.template))
uses the parameterized factory. Either replace the role when Firstmate is the
machine's main job, or layer the toolchain onto the laptop role:

```nix
# option 1 — Firstmate-only role (recommended for a Firstmate-run machine):
homeConfigurations.firstmate = nixdev-config.lib.mkStandalone {
  username = "you";
  homeDirectory = "/home/you";
  role = "firstmate";          # shell/git/dev common set + firstmate toolchain
};

# option 2 — keep the glab laptop role and layer the tools on:
homeConfigurations.laptop = nixdev-config.lib.mkStandalone {
  username = "you";
  homeDirectory = "/home/you";
  role = "laptop";             # glab stays; this profile never adds gh itself
  extraModules = [ nixdev-config.homeManagerModules.firstmateTools ];
};
```

Both are independent of each other — pick exactly one attribute per machine.
With option 2 the resulting activation has `glab` *and* `gh`; that is the
explicit opt-in the profile represents. Neither option declares a treehouse
input or an `extraSpecialArgs` — the standalone factory wires the exported
`packages.${system}.treehouse` internally. Only an external NixOS-style
caller (next section) passes the export explicitly.

Add the Herdr backend with an extra module (either option):

```nix
extraModules = [
  nixdev-config.homeManagerModules.firstmateTools
  { nixdev.firstmate.enableHerdr = true; }
];
```

Activate exactly as in docs/home-manager.md:

```bash
cd ~/.config/home-manager
home-manager switch --flake .#firstmate   # or .#laptop with option 2
```

## Public package export (one treehouse pin, zero consumer inputs)

The pinned treehouse package is exported from this flake as
**`packages.${system}.treehouse`** (same derivation the standalone factory and
the devShell use — `lib/firstmate.nix` and `packageLists` are the single
sources, so there is exactly one treehouse pin in the dependency tree):

- `lib.mkStandalone` wires it automatically — the standalone laptop flow
  never needs to mention it.
- **External Home Manager consumers (nixos-config) get it from this flake's
  public outputs and pass it through explicit `extraSpecialArgs`.** No
  consumer declares its own treehouse flake input, so nixos-config ends up
  with a single `nixdev-config` input for the whole Firstmate toolchain.
- Package ownership stays here (the pins in `flake.lock` and
  `lib/firstmate.nix`); machine-owned Treehouse **capacity** — its
  workspaces/sessions/state under the machine home, and whatever Firstmate
  home/runtime settings the machine keeps — stays consumer-owned and is
  never declared in this flake.

## Enabling it — desktop (NixOS-side Home Manager)

The desktop consumes this flake through nixos-config (the integration PR
lives in the **nixos-config** repository, out of scope here). The import
surface this repo guarantees:

```nix
# nixos-config side (later PR): home-manager.users.<name> = { ... };
# The module needs the pinned treehouse package, supplied from THIS flake's
# public output via extraSpecialArgs — no second treehouse flake input:
home-manager.extraSpecialArgs = {
  treehousePkg = nixdev-config.packages.${pkgs.system}.treehouse;
};

home-manager.users.linhnt = {
  imports = [
    nixdev-config.homeManagerModules.desktop   # gh role, as today
    nixdev-config.homeManagerModules.firstmate # or .firstmateTools to keep
  ];                                          # the laptop doc's layering
  nixdev.firstmate.enableHerdr = true;        # only if the machine runs Herdr
};
```

`homeManagerModules.firstmate` is the complete role profile (common modules +
toolchain); `homeManagerModules.firstmateTools` is just the toolchain layer
for composing onto the existing desktop/laptop profile. The desktop's own
local firstmate module in nixos-config can be replaced by this one; versions
match by design. The same call shape — public module + exported package via
explicit `extraSpecialArgs` — is regression-tested offline by
`scripts/check.sh` (external-consumer build, tmux ± herdr variants).

## After enabling: clone Firstmate and run its bootstrap

The profile installs *tools only*. Firstmate itself is a clone of the
machine fork origin <https://github.com/linhnt89/firstmate> (upstream:
<https://github.com/kunchenguid/firstmate>), bootstrapped per machine:

```bash
# 1. clone the machine fork (both the fork and its upstream are public —
#    nothing here is a private repo). On the MetaCube desktop the
#    portable home is /home/linhnt/firstmate; on the laptop, clone it
#    wherever that machine keeps its Firstmate home (e.g. ~/firstmate;
#    keep it out of Nix-managed dirs):
git clone https://github.com/linhnt89/firstmate /home/linhnt/firstmate
cd /home/linhnt/firstmate
#    add the public upstream so fixes that land there can be pulled in:
git remote add upstream https://github.com/kunchenguid/firstmate
#    data/ state/ config/ projects/ inside that home are gitignored
#    per-machine content (auth, harness choice, project clones) — never
#    part of this repo or its Nix profile.

# 2. the bootstrap detects what is missing given the toolchain the profile
#    now provides (node, git, gh, tmux, jq, the axi CLIs, treehouse,
#    no-mistakes are already present — it will mostly report auth):
bin/fm-bootstrap.sh

# 3. approve the automatic installs it asks for, then authenticate GitHub:
gh auth login          # stores credentials in ~/.config/gh — never in Nix

# 4. daily entry:
bin/fm-session-start.sh
```

Syncing the machine clone later (origin is the fork, upstream is
kunchenguid/firstmate):

```bash
cd /home/linhnt/firstmate
git pull                          # pull your own fork's tracked updates
git fetch --all                   # or fetch everything, incl. upstream
git merge upstream/main           # bring in kunchenguid/firstmate fixes
```

Merging tracked files never touches the gitignored per-machine `data/`,
`state/`, `config/`, `projects/` directories — they stay local to each
machine's home.

Claude Code, the primary assistant, stays a **native install** (see
docs/claude-code.md): it is deliberately not Nix-pinned so it can update on
its own schedule. Nothing in this profile changes that.

Firstmate's own `data/`, `state/`, `config/` (backend choice, crew harness,
dispatch profiles, tokens) remain in its home directory and are **never**
touched by this profile.

## Update and tool boundaries

- **Never self-update Nix-managed tools** (docs/updates.md). The Firstmate
  binaries here are immutable in the Nix store; their versions move only when
  this repo's pins move, via a deliberate PR:
  - axi CLIs: Dependabot's npm lane for `firstmate/node-tools` proposes
    version bumps (`package.json` + regenerated `package-lock.json`); every
    such PR must pass `scripts/check.sh` before merge.
  - `no-mistakes` / `herdr`: bump the version, URL, and SRI hash in
    `lib/firstmate.nix` (hashes from the upstream release checksums).
  - `crew-watch`: bump the pinned rev (git tag commit), source hash, and
    `cargoHash` in `lib/firstmate.nix` (source-built; hashes from
    `nix-prefetch-url --unpack` + a build, or the upstream release).
  - `treehouse`: bump the `treehouse.url` ref in `flake.nix` and re-lock
    (`nix flake lock treehouse`); it follows the `nixpkgs-unstable` lane.
    The exported `packages.${system}.treehouse` reflects the input
    automatically — consumers inherit the bump with no lock change of
    their own.
- Dependabot opens weekly PRs per lane: the nix stable lane (grouped), the
  `nixpkgs-unstable` and `treehouse` lanes (deliberate, not grouped), and an
  npm lane for `firstmate/node-tools` (the pinned axi CLIs). The URL/SRI
  pinned release assets (no-mistakes, herdr) and the source-pinned
  crew-watch build are not auto-bumped by Dependabot — that is intentional
  (they need a version+hash edit, like the pinned installers Firstmate
  itself ships).
- The firstmate devShell (`nix develop .#firstmate`) and the Home Manager
  module build from the same `lib/firstmate.nix`, so they cannot drift.
- `scripts/check.sh` builds the firstmate devShell and the firstmate role
  profile (with and without the Herdr backend) non-activating on every run.

## Boundaries (nothing new, just explicit)

No credentials, no git identity, no remotes, no SSH host blocks, no provider
or model settings, no Firstmate source/state, no `gh auth` data, no
`~/.claude/`, no `~/.pi/` data, no `data/`/`state/`/`config/` from a Firstmate
home. Runtime state belongs to the machine (`~/.config/gh`, `~/.ssh`,
`~/.claude`, `~/.pi/agent`, the Firstmate home). The no-secrets scan in
`scripts/check.sh` enforces the same boundary repo-wide
([assistant-tooling.md](assistant-tooling.md)).

**Package vs configuration ownership.** This flake owns the pinned packages
(`packages.${system}.treehouse`, `lib/firstmate.nix` assets, the devShell and
the profile wiring around them). It does **not** own any machine's Treehouse
capacity — Treehouse workspaces/sessions and their state under the machine
home are consumer-owned — nor any Firstmate home/runtime setting. Consumers
get the package from the public export and keep their capacity/config
machine-local; nothing here reads or writes either.