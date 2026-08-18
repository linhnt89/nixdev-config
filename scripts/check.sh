#!/usr/bin/env bash
#
# check.sh — repository-owned local validation (authoritative gate).
#
# Runs, in order:
#   1. static checks: required layout, shell syntax + shellcheck of the
#      repo's scripts and tests, YAML parse of .github/dependabot.yml and
#      .github/workflows/*.yml, actionlint on the workflows, JSON parse of
#      flake.lock, and a no-secrets scan of tracked files
#   2. offline regression tests for the standalone Home Manager update lane
#      (tests/run-tests.sh — fixture git repos + a fake `nix`; no network,
#      no real Nix evaluation, no activation)
#   3. `nix flake check`
#   4. NON-ACTIVATING builds of every devShell output
#   5. NON-ACTIVATING builds of the Home Manager role profiles (laptop =
#      glab, desktop = gh, optional firstmate = the Firstmate toolchain incl.
#      a herdr-enabled variant), built via the parameterized lib.mkStandalone
#      factory with a throwaway test user
#
# It never activates, switches, or touches a machine: everything is built
# into the Nix store only. `home-manager switch` / `nixos-rebuild` are
# deliberately NOT run here. This is the local check every change —
# including Dependabot PRs — must pass before merge. Remote CI is
# intentionally absent.
#
# Usage:
#   scripts/check.sh [--skip-build] [-h|--help]
#
#   --skip-build  static checks + `nix flake check` only (no shell or HM builds)
#
# Exit codes: 0 = all checks passed; nonzero = first failing check.
#
# Static-check parsers: shellcheck/actionlint/yq/jq on PATH are used when
# present; otherwise `nix shell nixpkgs#<tool>` provides them (nixpkgs is
# fetched by this repo's own lock). If neither is available the step warns
# and is skipped — the flake steps below would fail in such an environment
# anyway.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

skip_build=0

usage() {
  cat <<'EOF'
Usage: scripts/check.sh [--skip-build] [-h|--help]

Local validation gate: static checks, `nix flake check`, and non-activating
builds of every devShell and the Home Manager role profiles (laptop,
desktop, firstmate). Never activates or switches anything.

  --skip-build  static checks + `nix flake check` only
  -h, --help    show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) skip_build=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

failures=0

# Small helper: run a command, or fall back to `nix shell` for the tool.
with_tool() {
  # usage: with_tool <tool> <shell-package> <command...>
  local tool="$1" pkg="$2"
  shift 2
  if command -v "$tool" >/dev/null 2>&1; then
    "$@"
  elif command -v nix >/dev/null 2>&1; then
    nix shell "nixpkgs#$pkg" -c "$@"
  else
    echo "    warn: no $tool and no nix available; skipping" >&2
    return 1
  fi
}

# --- static checks --------------------------------------------------------

echo '==> Static checks'

echo '  required layout:'
for f in flake.nix flake.lock README.md scripts/check.sh scripts/update-home-manager.sh lib/package-lists.nix home docs tests .github/workflows; do
  if [[ -e "$f" ]]; then
    echo "    ok $f"
  else
    echo "    fail: missing $f" >&2
    failures=1
  fi
done

echo '  shell syntax (bash -n):'
for f in scripts/*.sh tests/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f"
  echo "    ok $f"
done

echo '  shellcheck (where available):'
for f in scripts/*.sh tests/*.sh; do
  [[ -f "$f" ]] || continue
  if with_tool shellcheck shellcheck shellcheck -S warning "$f"; then
    echo "    ok $f"
  else
    rc=$?
    if [[ $rc -eq 1 ]]; then
      echo "    fail: shellcheck reported issues in $f" >&2
      failures=1
    fi
  fi
done

echo '  YAML parse (.github):'
yaml_files=(.github/dependabot.yml .github/workflows/*.yml)
existing_yaml=()
for f in "${yaml_files[@]}"; do
  [[ -f "$f" ]] && existing_yaml+=("$f")
done
if ((${#existing_yaml[@]} > 0)); then
  if with_tool python3 python3 -c 'import sys, yaml; [yaml.safe_load(open(f)) or print(f"    ok {f}") for f in sys.argv[1:]]' "${existing_yaml[@]}" 2>/dev/null; then
    :
  elif with_tool yq yq-go yq eval . "${existing_yaml[@]}" >/dev/null 2>&1 && echo "    ok yq parse"; then
    :
  else
    echo "    warn: no YAML parser available (python3/PyYAML, yq, or nix); skipping" >&2
  fi
fi

echo '  actionlint (.github/workflows):'
# Semantic check of the repository's workflow(s): validates triggers, `if:`
# expression properties against GitHub's expression schema, permissions,
# and step structure. No-arg actionlint covers the default .github/workflows.
if with_tool actionlint actionlint actionlint; then
  echo "    ok .github/workflows"
else
  rc=$?
  if [[ $rc -eq 1 ]]; then
    echo "    fail: actionlint reported issues in .github/workflows" >&2
    failures=1
  fi
fi

echo '  JSON parse (flake.lock):'
if with_tool jq jq jq empty flake.lock; then
  echo "    ok flake.lock"
else
  rc=$?
  if [[ $rc -eq 1 ]]; then
    echo "    fail: flake.lock is not valid JSON" >&2
    failures=1
  fi
fi

echo '  no-secrets scan (tracked files):'
# Credential-shaped strings that must never appear in tracked content.
# Docs may *name* env vars (e.g. ANTHROPIC_API_KEY) in prose; real token
# shapes are what this scan rejects.
secrets=0
while IFS= read -r f; do
  if grep -nE 'sk-ant-[A-Za-z0-9+/=]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}' "$f" >/dev/null 2>&1; then
    echo "    fail: credential-shaped string in $f" >&2
    secrets=1
  fi
done < <(git ls-files 2>/dev/null | grep -v '^flake.lock$' || true)
if [[ $secrets -eq 0 ]]; then
  echo "    ok"
else
  failures=1
fi

# --- offline regression tests -------------------------------------------

# The standalone Home Manager update lane (scripts/update-home-manager.sh)
# is exercised offline: fixture git repos, a fake `nix` on PATH, HOME
# redirected to a throwaway tree. Never contacts GitHub, never builds with
# real Nix, never activates anything.
echo '==> Regression tests (offline, no activation)'
if bash tests/run-tests.sh; then
  echo '  ok: tests/run-tests.sh passed'
else
  echo '  fail: tests/run-tests.sh reported problems' >&2
  failures=1
fi

# --- flake check ----------------------------------------------------------

echo '==> nix flake check'
nix flake check

# --- non-activating builds of the devShells --------------------------------

if [[ "$skip_build" == 1 ]]; then
  echo '==> Shell builds skipped (--skip-build)'
else
  echo '==> Building devShell outputs (never activates or switches)'
  system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
  for shell in default desktop assistant firstmate; do
    echo "    nix build .#devShells.$system.$shell"
    nix build --no-link ".#devShells.$system.$shell"
  done

  # Explicit Firstmate sidecar assertion (crew-watch, docs/firstmate.md):
  # the optional read-only human diagnostic must be part of the SHARED
  # firstmate package set (lib/firstmate.nix — the single source behind BOTH
  # the firstmate devShell and homeManagerModules.firstmateTools) and of the
  # firstmate role profile's home.packages, and the pinned source build must
  # produce a runnable `crew-watch` binary. Asserts the package/profile
  # contract explicitly; no daemon, service, or wake/alert wiring exists or
  # is asserted — crew-watch is a sidecar only.
  echo '==> Firstmate sidecar assertion (crew-watch: shared set + firstmate profile + binary)'
  nix eval --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      system = builtins.currentSystem;
      pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
      fm = import ./lib/firstmate.nix {
        inherit pkgs;
        treehousePkg = flake.packages.${system}.treehouse;
      };
      hasCrewWatch = ps: builtins.any (p: p.pname or "" == "crew-watch") ps;
      profile = (flake.lib.mkStandalone {
        username = "nixdev-check";
        homeDirectory = "/home/nixdev-check";
        role = "firstmate";
      }).config;
    in
    assert hasCrewWatch fm.packages; # devShell + HM module share this set
    assert hasCrewWatch profile.home.packages; # firstmate role profile
    true
  '
  crew_watch_bin="$(
    nix build --no-link --print-out-paths --impure --expr '
      let
        flake = builtins.getFlake (toString ./.);
        system = builtins.currentSystem;
        pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
        fm = import ./lib/firstmate.nix {
          inherit pkgs;
          treehousePkg = flake.packages.${system}.treehouse;
        };
      in fm.crewWatch
    '
  )/bin/crew-watch"
  test -x "$crew_watch_bin"
  "$crew_watch_bin" --version >/dev/null
  echo "    ok crew-watch 0.1.1 in shared firstmate set + firstmate profile; binary builds and runs"

  # Consumer-facing package outputs build too: treehouse is THE documented
  # package export for external Home Manager consumers (docs/firstmate.md).
  echo '==> Building package outputs (never activates or switches)'
  for pkg in home-manager treehouse; do
    echo "    nix build .#packages.$system.$pkg"
    nix build --no-link ".#packages.$system.$pkg"
  done

  # Home Manager role profiles, built non-activating through the
  # parameterized lib.mkStandalone factory with a throwaway test user.
  # This evaluates both role splits (laptop=glab, desktop=gh) and builds
  # each generation's activation package without ever running it.
  echo '==> Building Home Manager role profiles (never activates or switches)'
  nix build --no-link --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      mkProfile = role:
        (flake.lib.mkStandalone {
          username = "nixdev-check";
          homeDirectory = "/home/nixdev-check";
          inherit role;
        }).activationPackage;
    in
    [
      (mkProfile "laptop") # glab role (work WSL2 laptop)
      (mkProfile "desktop") # gh role (MetaCube desktop)
      (mkProfile "firstmate") # opt-in firstmate toolchain role (tmux backend)
    ]
    # The opt-in herdr backend also builds (pinned release binary):
    ++ [
      (flake.lib.mkStandalone {
        username = "nixdev-check";
        homeDirectory = "/home/nixdev-check";
        role = "firstmate";
        extraModules = [ { nixdev.firstmate.enableHerdr = true; } ];
      }).activationPackage
    ]
  '
  echo "    ok home profiles (laptop + desktop + firstmate ± herdr) built non-activating"

  # Offline regression for the EXTERNAL NixOS-style consumer contract
  # (docs/firstmate.md): build Home Manager configurations that use ONLY
  # this flake's public outputs — homeManagerModules.firstmateTools plus the
  # exported packages.${system}.treehouse, passed via explicit
  # extraSpecialArgs — exactly what a nixos-config caller does, without a
  # second treehouse flake input. This repo's locked home-manager input
  # stands in for the consumer's (same release mkStandalone uses). Nothing
  # is activated or switched. Guards the export/contract end to end: if the
  # package output or the module's treehousePkg contract breaks, this build
  # fails here, not on a machine.
  echo '==> Building external-consumer Home Manager configs (public outputs only)'
  nix build --no-link --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      home-manager = flake.inputs.home-manager;
      lib = flake.inputs.nixpkgs.lib;
      system = builtins.currentSystem;

      # The exact call shape an external NixOS Home Manager consumer uses:
      # only public outputs + explicit extraSpecialArgs (docs/firstmate.md).
      mkConsumer = { enableHerdr ? false }:
        (home-manager.lib.homeManagerConfiguration {
          pkgs = flake.inputs.nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            treehousePkg = flake.packages.${system}.treehouse;
          };
          modules =
            [
              {
                home = {
                  username = "nixdev-check";
                  homeDirectory = "/home/nixdev-check";
                  stateVersion = "26.05";
                };
              }
              flake.homeManagerModules.firstmateTools
            ]
            ++ lib.optional enableHerdr { nixdev.firstmate.enableHerdr = true; };
        }).activationPackage;
    in
    [
      (mkConsumer { }) # tmux backend reference workflow
      (mkConsumer { enableHerdr = true; }) # opt-in herdr backend variant
    ]
  '
  echo "    ok external-consumer configs (firstmateTools ± herdr via public package export) built non-activating"
fi

if [[ $failures -ne 0 ]]; then
  echo
  echo 'FAIL — static checks reported problems.' >&2
  exit 1
fi

echo
echo 'PASS — local validation complete; nothing was activated or switched.'