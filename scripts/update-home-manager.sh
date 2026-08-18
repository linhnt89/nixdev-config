#!/usr/bin/env bash
#
# update-home-manager.sh — laptop companion lane for the standalone Home
# Manager profile.
#
# The laptop consumes the public nixdev-config checkout directly: the
# personal wrapper flake at ~/.config/home-manager/flake.nix points at it
# with a `path:` input (docs/home-manager.md). This script is the
# update/apply lane for that setup:
#
#   1. validates the checkout wants updating at all (clean, on the default
#      branch, fast-forwardable, unambiguous remote);
#   2. fast-forwards it from its configured remote;
#   3. re-locks the wrapper's `nixdev-config` input to the new revision;
#   4. builds the selected profile with the repo's pinned home-manager CLI;
#   5. ACTIVATES ONLY when --switch (or --apply) is passed.
#
# The PC uses the separate nixos-config/scripts/update-nixdev-config.sh
# lane instead; this script is for the standalone wrapper on the laptop
# (and any Linux box that consumes this checkout the same way).
#
# Guarantees:
#   * NON-ACTIVATING by default — build only. Activation is always opt-in.
#   * Refuses dirty, detached, conflicted, diverged (non-fast-forwardable),
#     or ambiguous source states; refuses when the wrapper does not point at
#     the checkout being updated, when the profile/remote cannot be
#     resolved unambiguously, or when the checkout is not on the branch it
#     is supposed to track.
#   * Inspects the wrapper read-only. Never edits flake.nix or any private
#     file. The only wrapper mutation is `nix flake lock --update-input
#     nixdev-config` (regenerating the generated flake.lock so it records
#     the new checkout revision — the point of an update) plus, on
#     --switch, a timestamped backup of that flake.lock first.
#   * Never resets, stashes, cleans, or discards anything in the checkout;
#     never touches credentials, git identity, credential stores,
#     assistant/runtime state, or generated Home Manager files outside the
#     requested update/activation.
#   * Never runs nixos-rebuild, system services, or desktop activation.
#   * Build, network, or authentication failures stop before any activation
#     and leave both the checkout and the wrapper fully inspectable.
#
# Usage:
#   scripts/update-home-manager.sh [options]
#
# Options:
#   --checkout DIR      nixdev-config checkout to fast-forward. Auto-detected
#                       (run from inside the checkout, else from the
#                       wrapper's nixdev-config input path, else the default
#                       $HOME/firstmate/projects/nixdev-config when present).
#   --wrapper DIR       wrapper directory with flake.nix
#                       (default: $HOME/.config/home-manager, the path the
#                       home-manager CLI auto-discovers).
#   --profile NAME      homeConfigurations.<NAME> to build/switch; accepts
#                       "laptop", "homeConfigurations.laptop", or ".#laptop".
#                       Auto-detected when the wrapper defines exactly one.
#   --flake [DIR][#NAME]  shorthand setting --wrapper and/or --profile,
#                       mirroring `home-manager --flake DIR#NAME` syntax.
#   --remote NAME       git remote to fetch from (required when the checkout
#                       has more than one remote).
#   --branch NAME       branch to fast-forward (default: the remote's HEAD /
#                       default branch; the checkout must already be on it).
#   --dry-run           read-only preflight: validate the checkout and
#                       wrapper, resolve remote/branch/profile, print the
#                       exact commands a real run would execute. No fetch,
#                       no build, no writes.
#   --switch            opt-in activation: update + build, then switch the
#                       profile via the pinned home-manager CLI and print
#                       rollback/generation guidance.
#   --apply             alias for --switch.
#   -h, --help          show this help.
#
# Exit codes: 0 = success; 1 = operational refusal/failure (nothing was
# activated unless the switch itself printed success); 2 = usage error.
#
# See docs/home-manager.md ("Updating the laptop's standalone profile") for
# the full picture, including rollback.

set -euo pipefail

# ---------------------------------------------------------------- arguments

dry_run=0
do_switch=0
opt_checkout=""
opt_wrapper=""
opt_profile=""
opt_remote=""
opt_branch=""

usage() {
  # The leading comment block doubles as the help text.
  sed -n '2,$p' "${BASH_SOURCE[0]}" | sed -n '/^#/!q;p' | sed 's/^# \{0,1\}//'
}

die() {
  printf 'update-home-manager: error: %s\n' "$*" >&2
  exit 1
}

usage_err() {
  {
    printf 'update-home-manager: %s\n' "$*"
    echo
    usage
  } >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checkout)
      [[ $# -ge 2 ]] || usage_err "--checkout needs a directory argument"
      opt_checkout="$2"
      shift 2
      ;;
    --wrapper)
      [[ $# -ge 2 ]] || usage_err "--wrapper needs a directory argument"
      opt_wrapper="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || usage_err "--profile needs a name argument"
      opt_profile="${2#homeConfigurations.}"
      opt_profile="${opt_profile#.\#}"
      shift 2
      ;;
    --flake)
      [[ $# -ge 2 ]] || usage_err "--flake needs a DIR[#NAME] argument"
      flake_arg="$2"
      shift 2
      if [[ "$flake_arg" == *'#'* ]]; then
        [[ -n "${flake_arg%%#*}" ]] && opt_wrapper="${flake_arg%%#*}"
        if [[ -n "${flake_arg#*#}" ]]; then
          opt_profile="${flake_arg#*#}"
          opt_profile="${opt_profile#homeConfigurations.}"
          opt_profile="${opt_profile#.\#}"
        fi
      else
        opt_wrapper="$flake_arg"
      fi
      ;;
    --remote)
      [[ $# -ge 2 ]] || usage_err "--remote needs a name argument"
      opt_remote="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || usage_err "--branch needs a name argument"
      opt_branch="$2"
      shift 2
      ;;
    --switch | --apply)
      do_switch=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      usage_err "unknown option: $1"
      ;;
    -*)
      usage_err "unknown option: $1"
      ;;
    *)
      usage_err "unexpected argument: $1"
      ;;
  esac
done

if [[ $dry_run -eq 1 && $do_switch -eq 1 ]]; then
  usage_err "--dry-run cannot be combined with --switch/--apply"
fi

# ------------------------------------------------------ resolve the checkout

wrapper="${opt_wrapper:-$HOME/.config/home-manager}"
default_checkout="$HOME/firstmate/projects/nixdev-config"

# wrapper_input_checkout — print the canonical path the wrapper's
# `nixdev-config` input points at; exit nonzero when it cannot be
# determined or is not a `path:` input.
wrapper_input_checkout() {
  local wf="$1" line url
  line="$(
    sed -n -e '/^[[:space:]]*#/d' \
      -e 's/.*nixdev-config[[:space:]]*\.url[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$wf" 2>/dev/null | tail -n 1 || true
  )"
  [[ -n "$line" ]] || return 1
  case "$line" in
    path:*) url="${line#path:}" ;;
    *) return 2 ;; # not a path: input; the lane requires one
  esac
  url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  if [[ "$url" = /* ]]; then
    realpath "$url" 2>/dev/null || return 1
  else
    realpath -m "$(dirname -- "$wf")/$url" 2>/dev/null || return 1
  fi
}

checkout=""
if [[ -n "$opt_checkout" ]]; then
  [[ -e "$opt_checkout" ]] || die "--checkout: no such path: $opt_checkout"
  checkout="$(realpath "$opt_checkout")"
else
  # 1. running from inside a nixdev-config-looking checkout
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    && [[ -n "$root" && -f "$root/flake.nix" && -f "$root/lib/package-lists.nix" ]]; then
    checkout="$(realpath "$root")"
  else
    # 2. the wrapper's nixdev-config input path
    if [[ -f "$wrapper/flake.nix" ]]; then
      if parsed="$(wrapper_input_checkout "$wrapper/flake.nix" 2>/dev/null || true)"; then
        checkout="$parsed"
      fi
    fi
  fi
  if [[ -z "$checkout" ]]; then
    # 3. the documented default location for the laptop checkout
    if [[ -d "$default_checkout" && -f "$default_checkout/flake.nix" ]]; then
      checkout="$(realpath "$default_checkout")"
    else
      die "could not locate the nixdev-config checkout: pass --checkout, run from inside the checkout, or place it at $default_checkout"
    fi
  fi
fi

# ------------------------------------------------------------ source state

[[ -d "$checkout" ]] || die "checkout directory does not exist: $checkout"

if ! git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
  die "checkout is not a git repository: $checkout"
fi
[[ -f "$checkout/flake.nix" ]] || die "no flake.nix in $checkout — is this the nixdev-config checkout?"

current_branch="$(git -C "$checkout" rev-parse --abbrev-ref HEAD)"
if [[ "$current_branch" == "HEAD" ]]; then
  die "refusing: checkout is on a detached HEAD ($checkout); check out the branch it should track first"
fi

if git -C "$checkout" ls-files -u 2>/dev/null | grep -q .; then
  die "refusing: checkout has conflicted (unmerged) files; resolve them first"
fi

porcelain="$(git -C "$checkout" status --porcelain 2>/dev/null || true)"
if [[ -n "$porcelain" ]]; then
  die "refusing: checkout is dirty (incl. untracked files): $checkout; commit or move the changes elsewhere first (the lane never stashes/resets/cleans)"
fi

# --------------------------------------------------------------- remote

if [[ -n "$opt_remote" ]]; then
  remote="$opt_remote"
  git -C "$checkout" remote | grep -qxF "$remote" \
    || die "refusing: no such remote '$remote' (remotes: $(git -C "$checkout" remote | tr '\n' ' '))"
else
  remotes="$(git -C "$checkout" remote || true)"
  case "$(printf '%s\n' "$remotes" | grep -c . || true)" in
    0) die "refusing: checkout has no git remote; pass --remote or add one first" ;;
    1) remote="$remotes" ;;
    *)
      die "refusing: multiple remotes ($(printf '%s' "$remotes" | tr '\n' ' ')) make the fetch target ambiguous; pass --remote"
      ;;
  esac
fi

# ---------------------------------------------------------------- branch

# default_branch — the remote's HEAD/default branch. Tries the local
# remote-tracking symref first, then cached `remote show -n` info, then
# (network) `ls-remote --symref`. Prints nothing and returns nonzero when
# the branch cannot be determined.
default_branch() {
  local r="$1" sym out br
  if sym="$(git -C "$checkout" symbolic-ref -q "refs/remotes/$r/HEAD" 2>/dev/null)"; then
    printf '%s\n' "${sym##*/}" # refs/remotes/origin/main -> main
    return 0
  fi
  out="$(git -C "$checkout" remote show -n "$r" 2>/dev/null || true)"
  if br="$(printf '%s\n' "$out" | sed -n 's/^  HEAD branch: //p' | grep -v '(unknown)' | head -n 1)"; then
    if [[ -n "$br" ]]; then
      printf '%s\n' "$br"
      return 0
    fi
  fi
  out="$(git -C "$checkout" ls-remote --symref "$r" HEAD 2>/dev/null \
    | awk 'NR == 1 && $1 == "ref:" { sub("refs/heads/", "", $2); print $2 }' || true)"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
    return 0
  fi
  return 1
}

if [[ -n "$opt_branch" ]]; then
  branch="$opt_branch"
else
  branch="$(default_branch "$remote" || true)"
  if [[ -z "$branch" ]]; then
    die "refusing: cannot determine the default branch of remote '$remote'; pass --branch"
  fi
fi

if [[ "$current_branch" != "$branch" ]]; then
  die "refusing: checkout is on '$current_branch', not on target branch '$branch'; check out the branch it should track (the lane only fast-forwards the branch the checkout is on)"
fi

# ----------------------------------------------------------------- wrapper

[[ -d "$wrapper" ]] || die "wrapper directory does not exist: $wrapper (checkout resolved to $checkout; pass --wrapper or put flake.nix in $HOME/.config/home-manager)"
[[ -f "$wrapper/flake.nix" ]] || die "no flake.nix in wrapper directory: $wrapper (checkout resolved to $checkout)"

wrapper_input=""
if ! wrapper_input="$(wrapper_input_checkout "$wrapper/flake.nix" 2>/dev/null)"; then
  case $? in
    2) die "refusing: the wrapper's nixdev-config input is not a 'path:' input; the update lane requires the wrapper flake.nix to point at the local checkout with path:<dir> (see home/standalone/flake.nix.template)" ;;
    *) die "refusing: cannot determine the wrapper's nixdev-config input path from $wrapper/flake.nix (expected a line like: inputs.nixdev-config.url = \"path:/abs/path\";)" ;;
  esac
fi
if [[ "$wrapper_input" != "$checkout" ]]; then
  die "refusing: wrapper input resolves to $wrapper_input but the checkout is $checkout — updating one would not affect the other; align --checkout and the wrapper's path: input"
fi

# ---------------------------------------------------------------- profile

if [[ -n "$opt_profile" ]]; then
  profile="$opt_profile"
else
  profiles="$(
    grep -oE 'homeConfigurations\.([A-Za-z0-9_.-]+)' "$wrapper/flake.nix" 2>/dev/null \
      | sed 's/^homeConfigurations\.//' | sort -u || true
  )"
  case "$(printf '%s\n' "$profiles" | grep -c . || true)" in
    0) die "refusing: no homeConfigurations.<name> found in $wrapper/flake.nix; pass --profile" ;;
    1) profile="$profiles" ;;
    *) die "refusing: wrapper defines multiple profiles ($(printf '%s' "$profiles" | tr '\n' ' ')); pass --profile to select one" ;;
  esac
fi

# --------------------------------------------------------- preflight output

real_run() {
  printf '  git -C %s fetch %s %s\n' "$checkout" "$remote" "$branch"
  printf '  git -C %s merge --ff-only FETCH_HEAD\n' "$checkout"
  printf '  nix flake lock --update-input nixdev-config %s\n' "$wrapper"
  printf '  nix run %s#home-manager -- build --flake %s#%s\n' "$checkout" "$wrapper" "$profile"
  if [[ $do_switch -eq 1 ]]; then
    printf '  nix run %s#home-manager -- switch --flake %s#%s\n' "$checkout" "$wrapper" "$profile"
  fi
}

{
  echo "==> update-home-manager preflight"
  echo "  checkout: $checkout"
  echo "  branch:   $branch (currently on $current_branch)"
  echo "  remote:   $remote"
  echo "  wrapper:  $wrapper"
  echo "  wrapper nixdev-config input: path:$wrapper_input (matches the checkout)"
  echo "  profile:  homeConfigurations.$profile"
  if [[ $dry_run -eq 1 ]]; then
    echo "  mode:     dry-run — nothing will be fetched, built, written, or activated"
    echo "  would run:"
    real_run
    echo
    echo "  Re-run without --dry-run to execute; add --switch/--apply to activate."
  elif [[ $do_switch -eq 1 ]]; then
    echo "  mode:     update + build + SWITCH (activation requested)"
  else
    echo "  mode:     update + build only — no activation"
  fi
} >&2

if [[ $dry_run -eq 1 ]]; then
  exit 0
fi

# ------------------------------------------------------------------ update

echo "==> fetching from $remote ($branch)" >&2
git -C "$checkout" fetch "$remote" "$branch" \
  || die "fetch from '$remote' failed (network/authentication) — nothing was changed; the checkout and wrapper are untouched and inspectable"

if ! git -C "$checkout" merge-base --is-ancestor HEAD FETCH_HEAD 2>/dev/null; then
  die "refusing: '$branch' has diverged — local commits exist that the remote does not contain, so this is not a fast-forward; the lane never merges or rebases. Nothing was changed."
fi

echo "==> fast-forwarding $checkout" >&2
git -C "$checkout" merge --ff-only FETCH_HEAD >/dev/null \
  || die "refusing: fast-forward failed unexpectedly; nothing was changed"

post_porcelain="$(git -C "$checkout" status --porcelain 2>/dev/null || true)"
if [[ -n "$post_porcelain" ]]; then
  die "refusing: checkout became dirty during the update; stopping before the build (nothing was activated)"
fi

new_rev="$(git -C "$checkout" rev-parse --short HEAD)"

# Re-lock the wrapper's nixdev-config input to the checkout's new state.
# This is the only wrapper mutation (besides the flake.lock backup below);
# flake.nix and every private file stay untouched.
lock_backup=""
if [[ $do_switch -eq 1 && -f "$wrapper/flake.lock" ]]; then
  lock_backup="$wrapper/flake.lock.pre-update.$(date +%Y%m%d-%H%M%S)"
  cp -p "$wrapper/flake.lock" "$lock_backup"
  echo "  backed up wrapper lock: $lock_backup" >&2
fi

echo "==> re-locking wrapper input nixdev-config (writes only $wrapper/flake.lock)" >&2
nix flake lock --update-input nixdev-config "$wrapper" \
  || die "re-locking the wrapper input failed — the checkout is fast-forwarded but nothing was built or activated"

# ------------------------------------------------------------------- build

echo "==> building homeConfigurations.$profile (pinned home-manager CLI, never activates)" >&2
if ! nix run "$checkout"#home-manager -- build --flake "$wrapper#$profile"; then
  die "build failed — nothing was activated; the fast-forwarded checkout and the wrapper (re-locked to it) are intact and inspectable"
fi

# ---------------------------------------------------------------- activate

if [[ $do_switch -eq 1 ]]; then
  echo "==> switching homeConfigurations.$profile (requested activation)" >&2
  nix run "$checkout"#home-manager -- switch --flake "$wrapper#$profile" \
    || die "switch failed — no further rollback guidance from this script; inspect ~/.local/state/home-manager and run 'home-manager generations'"

  cat <<EOF
==> Activation complete for homeConfigurations.$profile (checkout at $new_rev).

Inspect generations:   home-manager generations
Rollback to previous:  home-manager rollback
  (home-manager rollback switches back one generation and is the primary
   undo for a bad activation.)

Pin the wrapper back to the nixdev-config revision used BEFORE this update
(only needed if you must freeze the old environment for future switches):

  cp $lock_backup $wrapper/flake.lock
  home-manager switch --flake $wrapper#$profile

The checkout itself still contains every previous commit — the fast-forward
only added history — so the old pinned state remains fully fetchable.
EOF
else
  cat <<EOF
==> Build OK; nothing was activated (checkout now at $new_rev).

To activate the built configuration:

  $0 --switch --checkout $checkout --wrapper $wrapper --profile $profile
EOF
fi