#!/usr/bin/env bash
#
# run-tests.sh — offline regression tests for scripts/update-home-manager.sh
# (the laptop companion update/apply lane for the standalone Home Manager
# wrapper).
#
# Everything is offline and disposable:
#   * fixture source/upstream git repositories created with real `git`
#     against local paths (no network, no GitHub, no real checkout);
#   * a fake `nix` on PATH stubs `nix flake lock` / `nix run ... home-manager`
#     (build/switch), so no real Nix evaluation or activation ever happens
#     and no machine's Home Manager is touched;
#   * HOME is redirected to a throwaway tree, so nothing outside the test
#     tmpdir can be modified.
#
# Coverage (per the lane's acceptance criteria):
#   - dirty / detached / conflicted / wrong-branch / no-remote /
#     multiple-remote / unknown-remote / diverged / wrapper-mismatch /
#     wrapper-missing / ambiguous-profile source refusals
#   - fetch (network/auth) failure leaves everything inspectable
#   - build failure never activates
#   - default run = fast-forward + build with NO activation
#   - --switch/--apply = explicit activation + rollback guidance
#   - private wrapper/runtime paths are preserved untouched
#   - --dry-run performs no fetch/build/write at all
#   - checkout auto-discovery (cwd and $HOME/firstmate/projects/nixdev-config)
#
# Wired into scripts/check.sh (runs between the static checks and
# `nix flake check`). Requires: bash, git, realpath. Does NOT require nix.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/update-home-manager.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/update-hm-test.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

home="$tmp/home"
mkdir -p "$home"
wrapper_dir="$home/.config/home-manager"
mkdir -p "$wrapper_dir"

passed=0
failed=0

pass() { passed=$((passed + 1)); printf '  ok: %s\n' "$1"; }
fail() {
  failed=$((failed + 1))
  printf '  FAIL: %s\n' "$1" >&2
  printf '    --- last stdout ---\n' >&2
  sed 's/^/    /' "$tmp/last.out" >&2 || true
  printf '    --- last stderr ---\n' >&2
  sed 's/^/    /' "$tmp/last.err" >&2 || true
}

run() {
  # usage: run [--expect-rc N] [--] script-args...
  local want_rc=""
  if [[ "${1:-}" == "--expect-rc" ]]; then
    want_rc="$2"
    shift 2
  fi
  [[ "${1:-}" == "--" ]] && shift
  set +e
  (
    cd "$tmp"
    HOME="$home"
    PATH="$tmp/bin:$PATH"
    export HOME PATH
    bash "$script" "$@" >"$tmp/last.out" 2>"$tmp/last.err"
  )
  local rc=$?
  set -e
  if [[ -n "$want_rc" ]]; then
    if [[ $rc -ne "$want_rc" ]]; then
      fail "expected rc $want_rc, got $rc"
      return 1
    fi
  fi
  return 0
}

err_has() { grep -q -- "$1" "$tmp/last.err"; }
out_has() { grep -q -- "$1" "$tmp/last.out"; }

nix_log() { cat "$tmp/nix.log" 2>/dev/null || true; }
log_has() { [[ -s "$tmp/nix.log" ]] && grep -q -- "$1" "$tmp/nix.log"; }

# ------------------------------------------------------------------ fixtures

# fake `nix`: stubs flake-lock / nix-run; logs every invocation to
# $FAKE_NIX_LOG; build/switch exit codes come from FAKE_NIX_BUILD_RC /
# FAKE_NIX_SWITCH_RC (default 0). `flake` writes a flake.lock into the
# wrapper dir like real `nix flake lock --update-input` would.
setup_fake_nix() {
  mkdir -p "$tmp/bin"
  cat >"$tmp/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nix %s\n' "$*" >> "${FAKE_NIX_LOG:?}"
case "${1:-}" in
  flake)
    # nix flake lock --update-input nixdev-config <wrapper-dir>
    printf '{"fake": true, "at": "%s"}\n' "$(date +%s)" > "${@: -1}/flake.lock"
    exit 0
    ;;
  run)
    # nix run <checkout>#home-manager -- build|switch --flake <wrapper>#<name>
    sub=build
    d=0
    for a in "$@"; do
      if [[ $d -eq 1 ]]; then sub="$a"; break; fi
      [[ "$a" == "--" ]] && d=1
    done
    case "$sub" in
      build) exit "${FAKE_NIX_BUILD_RC:-0}" ;;
      switch) exit "${FAKE_NIX_SWITCH_RC:-0}" ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$tmp/bin/nix"
}

# fixture_new NAME — creates:
#   $tmp/fixtures/NAME/upstream  (bare-ish source repo, gets a new commit)
#   $tmp/fixtures/NAME/checkout  (clone on main, tracking origin)
# and points the default wrapper at the checkout with one `laptop` profile.
# Global: sets UPSTREAM and CHECKOUT.
fixture_new() {
  local name="$1"
  local base="$tmp/fixtures/$name"
  UPSTREAM="$base/upstream"
  CHECKOUT="$base/checkout"
  mkdir -p "$UPSTREAM"
  git -C "$UPSTREAM" init -q -b main
  git -C "$UPSTREAM" config user.name tester
  git -C "$UPSTREAM" config user.email tester@example.invalid
  printf 'flake one\n' >"$UPSTREAM/flake.nix"
  mkdir -p "$UPSTREAM/lib"
  printf '{}\n' >"$UPSTREAM/lib/package-lists.nix"
  printf 'tracked file\n' >"$UPSTREAM/tracked.txt"
  git -C "$UPSTREAM" add -A
  git -C "$UPSTREAM" commit -qm one
  git clone -q "$UPSTREAM" "$CHECKOUT"
  wrapper_write laptop
  # upstream advances: the checkout is now one commit behind
  printf 'flake two\n' >>"$UPSTREAM/flake.nix"
  printf 'more tracked\n' >>"$UPSTREAM/tracked.txt"
  git -C "$UPSTREAM" add -A
  git -C "$UPSTREAM" commit -qm two
}

# wrapper_write PROFILES... — default wrapper flake with the given
# homeConfigurations.<name> attributes, its nixdev-config input pinned to
# the current $CHECKOUT.
wrapper_write() {
  local attrs=""
  for p in "$@"; do
    attrs+="  homeConfigurations.$p = nixdev-config.lib.mkStandalone { username=\"you\"; homeDirectory=\"/home/you\"; role=\"$p\"; };\n"
  done
  printf '{ inputs.nixdev-config.url = "path:%s"; outputs = { nixdev-config, ... }: {\n%b};\n}\n' \
    "$CHECKOUT" "$attrs" >"$wrapper_dir/flake.nix"
}

fixture_head() { git -C "$1" rev-parse HEAD; }

# -------------------------------------------------------------------- tests

echo "==> tests: scripts/update-home-manager.sh (offline, fake nix)"

setup_fake_nix
export FAKE_NIX_LOG="$tmp/nix.log"
export FAKE_NIX_BUILD_RC="" FAKE_NIX_SWITCH_RC=""

# --- help/usage ---------------------------------------------------------

rm -f "$tmp/nix.log"
run --expect-rc 0 -- --help
out_has 'update-home-manager.sh — laptop companion lane' && pass '--help shows the lane description' || fail '--help missing description'

run --expect-rc 2 -- --bogus-flag
err_has 'unknown option' && pass 'unknown option exits 2' || fail 'unknown option mishandled'

run --expect-rc 2 -- --dry-run --switch
err_has 'cannot be combined' && pass '--dry-run + --switch refused' || fail '--dry-run + --switch not refused'

# --- source-state refusals (all in --dry-run preflight) ------------------

fixture_new dirty
{
  printf 'untracked scratch\n' >"$CHECKOUT/scratch.txt"
  printf 'dirty\n' >>"$CHECKOUT/tracked.txt"
}
head_before="$(fixture_head "$CHECKOUT")"
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'dirty' && pass 'dirty checkout refused' || fail 'dirty checkout not refused'
[[ "$(fixture_head "$CHECKOUT")" == "$head_before" ]] && pass 'dirty refusal changes nothing' || fail 'dirty refusal changed HEAD'
git -C "$CHECKOUT" checkout -q -- tracked.txt
rm -f "$CHECKOUT/scratch.txt"

fixture_new detached
git -C "$CHECKOUT" checkout -q "$(fixture_head "$CHECKOUT")" # orphan/old rev -> detached
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'detached' && pass 'detached HEAD refused' || fail 'detached HEAD not refused'
git -C "$CHECKOUT" checkout -q main

fixture_new conflicted
git -C "$CHECKOUT" config user.name tester
git -C "$CHECKOUT" config user.email tester@example.invalid
git -C "$CHECKOUT" switch -q -c left
printf 'left\n' >"$CHECKOUT/conflict.txt"
git -C "$CHECKOUT" add conflict.txt
git -C "$CHECKOUT" commit -qm left
git -C "$CHECKOUT" switch -q main
printf 'main\n' >"$CHECKOUT/conflict.txt"
git -C "$CHECKOUT" add conflict.txt
git -C "$CHECKOUT" commit -qm main2
git -C "$CHECKOUT" merge --no-commit left || true # expected conflict
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'conflict' && pass 'conflicted checkout refused' || fail 'conflicted checkout not refused'
git -C "$CHECKOUT" merge --abort 2>/dev/null || true

fixture_new wrongbranch
git -C "$CHECKOUT" switch -q -c feature
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'not on target branch' && pass 'wrong branch refused' || fail 'wrong branch not refused'

# --- remote/branch problems ----------------------------------------------

fixture_new noremote
git -C "$CHECKOUT" remote remove origin
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'no git remote' && pass 'no remote refused' || fail 'no remote not refused'

fixture_new multiremote
git -C "$CHECKOUT" remote add backup /nonexistent/upstream.git
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'ambiguous' && pass 'multiple remotes refused' || fail 'multiple remotes not refused'

fixture_new unknownremote
run --expect-rc 1 -- --checkout "$CHECKOUT" --remote bogus --dry-run
err_has "no such remote 'bogus'" && pass 'unknown remote refused' || fail 'unknown remote not refused'

# diverged: local commit dangles behind origin/main — not fast-forwardable
fixture_new diverged
git -C "$CHECKOUT" config user.name tester
git -C "$CHECKOUT" config user.email tester@example.invalid
printf 'local\n' >"$CHECKOUT/local.txt"
git -C "$CHECKOUT" add local.txt
git -C "$CHECKOUT" commit -qm local-only
head_before="$(fixture_head "$CHECKOUT")"
run --expect-rc 1 -- --checkout "$CHECKOUT"
err_has 'not a fast-forward' && pass 'diverged branch refused (no merge/rebase)' || fail 'diverged branch not refused'
[[ "$(fixture_head "$CHECKOUT")" == "$head_before" ]] && pass 'diverged refusal changed nothing' || fail 'diverged refusal changed HEAD'

# fetch (network/auth) failure: remote URL points nowhere
fixture_new fetchfail
git -C "$CHECKOUT" remote set-url origin /nonexistent/upstream.git
head_before="$(fixture_head "$CHECKOUT")"
run --expect-rc 1 -- --checkout "$CHECKOUT"
err_has 'fetch from' && pass 'fetch failure reported' || fail 'fetch failure not reported'
[[ "$(fixture_head "$CHECKOUT")" == "$head_before" ]] && pass 'fetch failure left HEAD untouched' || fail 'fetch failure moved HEAD'
[[ ! -e "$wrapper_dir/flake.lock" ]] && pass 'fetch failure wrote nothing to wrapper' || fail 'fetch failure wrote wrapper lock'

# --- wrapper problems ----------------------------------------------------

fixture_new nowrapper
rm -f "$wrapper_dir/flake.nix"
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'no flake.nix in wrapper' && pass 'missing wrapper flake.nix refused' || fail 'missing wrapper flake.nix not refused'

fixture_new mismatch
git clone -q "$UPSTREAM" "$tmp/fixtures/mismatch/other"
other_checkout="$tmp/fixtures/mismatch/other"
printf '{ inputs.nixdev-config.url = "path:%s"; outputs = { nixdev-config, ... }: {\n  homeConfigurations.laptop = nixdev-config.lib.mkStandalone { username="you"; homeDirectory="/home/you"; role="laptop"; };\n};\n}\n' "$other_checkout" >"$wrapper_dir/flake.nix"
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'would not affect the other' && pass 'wrapper/checkout mismatch refused' || fail 'wrapper/checkout mismatch not refused'

# --- profile resolution --------------------------------------------------

fixture_new ambigprofile
wrapper_write laptop desktop
run --expect-rc 1 -- --checkout "$CHECKOUT" --dry-run
err_has 'multiple profiles' && pass 'ambiguous profile refused' || fail 'ambiguous profile not refused'
run --expect-rc 0 -- --checkout "$CHECKOUT" --profile laptop --dry-run
err_has 'homeConfigurations.laptop' && pass '--profile laptop resolves' || fail '--profile laptop failed'
run --expect-rc 0 -- --checkout "$CHECKOUT" --flake "$wrapper_dir#desktop" --dry-run
err_has 'homeConfigurations.desktop' && pass '--flake DIR#NAME resolves' || fail '--flake DIR#NAME failed'

wrapper_write laptop
run --expect-rc 0 -- --checkout "$CHECKOUT" --dry-run
err_has 'profile:  homeConfigurations.laptop' && pass 'single profile auto-detected' || fail 'single profile not auto-detected'

# --- dry-run performs no mutations ---------------------------------------

fixture_new dryrun
rm -f "$tmp/nix.log"
run --expect-rc 0 -- --checkout "$CHECKOUT" --dry-run
head_before="$(fixture_head "$CHECKOUT")"
[[ ! -e "$CHECKOUT/.git/FETCH_HEAD" ]] && pass 'dry-run performed no fetch' || fail 'dry-run fetched'
[[ ! -e "$wrapper_dir/flake.lock" ]] && pass 'dry-run wrote no wrapper lock' || fail 'dry-run wrote wrapper lock'
[[ ! -s "$tmp/nix.log" ]] && pass 'dry-run invoked no nix' || fail 'dry-run invoked nix'
[[ "$(fixture_head "$CHECKOUT")" == "$head_before" ]] && pass 'dry-run left HEAD untouched' || fail 'dry-run moved HEAD'

# --- default run: fast-forward + build, NO activation ----------------------

fixture_new defaultrun
rm -f "$tmp/nix.log"
run --expect-rc 0 -- --checkout "$CHECKOUT"
upstream_tip="$(fixture_head "$UPSTREAM")"
[[ "$(fixture_head "$CHECKOUT")" == "$upstream_tip" ]] && pass 'default run fast-forwarded the checkout' || fail 'default run did not fast-forward'
log_has 'build' && pass 'default run built the profile' || fail 'default run did not build'
if log_has 'switch'; then fail 'default run activated (switch must be opt-in)'; else pass 'default run did NOT activate'; fi
[[ -e "$wrapper_dir/flake.lock" ]] && pass 'default run re-locked the wrapper input' || fail 'default run did not re-lock wrapper'
out_has 'nothing was activated' && pass 'default run says nothing activated' || fail 'default run did not state no-activation'
[[ -z "$(git -C "$CHECKOUT" status --porcelain)" ]] && pass 'checkout clean after default run' || fail 'checkout dirty after default run'
if compgen -G "$wrapper_dir/flake.lock.pre-update.*" >/dev/null; then
  fail 'lock backup created without --switch'
else
  pass 'no lock backup without --switch'
fi

# --- explicit switch: activation + rollback guidance -----------------------

fixture_new switchrun
rm -f "$tmp/nix.log"
run --expect-rc 0 -- --checkout "$CHECKOUT" --switch
log_has 'switch' && pass '--switch activated the profile' || fail '--switch did not activate'
out_has 'home-manager rollback' && pass 'rollback guidance printed' || fail 'rollback guidance missing'
out_has 'home-manager generations' && pass 'generations guidance printed' || fail 'generations guidance missing'
if compgen -G "$wrapper_dir/flake.lock.pre-update.*" >/dev/null; then
  pass '--switch took a lock backup'
else
  fail '--switch did not back up the lock'
fi
[[ -z "$(git -C "$CHECKOUT" status --porcelain)" ]] && pass 'checkout clean after switch' || fail 'checkout dirty after switch'

fixture_new applyrun
rm -f "$tmp/nix.log"
run --expect-rc 0 -- --checkout "$CHECKOUT" --apply
log_has 'switch' && pass '--apply is an alias for --switch' || fail '--apply did not activate'

# --- build failure: nothing activated, everything inspectable -------------

fixture_new buildfail
rm -f "$tmp/nix.log"
FAKE_NIX_BUILD_RC=42
run --expect-rc 1 -- --checkout "$CHECKOUT"
FAKE_NIX_BUILD_RC=""
upstream_tip="$(fixture_head "$UPSTREAM")"
err_has 'build failed' && pass 'build failure reported' || fail 'build failure not reported'
[[ "$(fixture_head "$CHECKOUT")" == "$upstream_tip" ]] && pass 'build failure left checkout fast-forwarded (inspectable)' || fail 'build failure did not fast-forward'
log_has 'build' && pass 'build attempted' || fail 'build not attempted'
if log_has 'switch'; then fail 'build failure still activated'; else pass 'build failure never activated'; fi
[[ -e "$wrapper_dir/flake.lock" ]] && pass 'build failure left wrapper re-locked (inspectable)' || fail 'build failure lost wrapper lock'
git -C "$CHECKOUT" status --porcelain | grep -q . && fail 'build failure dirtied checkout' || pass 'build failure left checkout clean'

# switch failure also reports and guides inspection
fixture_new switchfail
rm -f "$tmp/nix.log"
FAKE_NIX_SWITCH_RC=42
run --expect-rc 1 -- --checkout "$CHECKOUT" --switch
FAKE_NIX_SWITCH_RC=""
err_has 'switch failed' && pass 'switch failure reported' || fail 'switch failure not reported'
err_has 'home-manager generations' && pass 'switch failure points at generations' || fail 'switch failure lacks inspection hint'

# --- preservation of private/wrapper/runtime paths --------------------------

fixture_new preserve
mkdir -p "$home/.ssh" "$home/.claude" "$home/.pi"
printf 'ssh marker\n' >"$home/.ssh/marker"
printf 'claude marker\n' >"$home/.claude/marker"
printf 'pi marker\n' >"$home/.pi/marker"
printf 'private extra module\n' >"$wrapper_dir/extra.nix"
printf 'private note\n' >"$wrapper_dir/private.txt"
checksum_wrapper="$(cksum "$wrapper_dir/flake.nix" "$wrapper_dir/extra.nix" "$wrapper_dir/private.txt")"
run --expect-rc 0 -- --checkout "$CHECKOUT" --switch
grep -q 'ssh marker' "$home/.ssh/marker" && pass 'runtime ~/.ssh untouched' || fail 'runtime ~/.ssh modified'
grep -q 'claude marker' "$home/.claude/marker" && pass 'runtime ~/.claude untouched' || fail 'runtime ~/.claude modified'
grep -q 'pi marker' "$home/.pi/marker" && pass 'runtime ~/.pi untouched' || fail 'runtime ~/.pi modified'
[[ "$(cksum "$wrapper_dir/flake.nix" "$wrapper_dir/extra.nix" "$wrapper_dir/private.txt")" == "$checksum_wrapper" ]] \
  && pass 'wrapper flake.nix/extra files byte-identical' || fail 'wrapper private files modified'
if git -C "$CHECKOUT" reflog | grep -qiE 'reset|stash|clean'; then
  fail 'checkout reflog shows destructive git commands'
else
  pass 'no destructive git commands in reflog'
fi
[[ -z "$(git -C "$CHECKOUT" status --porcelain)" ]] && pass 'checkout clean after preserve run' || fail 'checkout dirty after preserve run'

# --- checkout auto-discovery ----------------------------------------------

# from inside the checkout (no --checkout, default wrapper)
fixture_new discover
rm -f "$tmp/nix.log"
set +e
(
  cd "$CHECKOUT"
  HOME="$home"
  PATH="$tmp/bin:$PATH"
  export HOME PATH
  bash "$script"
) >"$tmp/last.out" 2>"$tmp/last.err"
discover_rc=$?
set -e
if [[ $discover_rc -eq 0 && "$(fixture_head "$CHECKOUT")" == "$(fixture_head "$UPSTREAM")" ]]; then
  pass 'auto-discovery from checkout cwd'
else
  fail "auto-discovery from checkout cwd (rc=$discover_rc)"
fi

# from the documented default location under $HOME (wrapper missing: the
# checkout must resolve to $HOME/firstmate/projects/nixdev-config)
rm -rf "$tmp/home/firstmate"
rm -rf "$wrapper_dir"
mkdir -p "$tmp/home/firstmate/projects"
git clone -q "$UPSTREAM" "$tmp/home/firstmate/projects/nixdev-config"
run --expect-rc 1 -- --dry-run
err_has 'firstmate/projects/nixdev-config' && pass 'default checkout location auto-detected' || fail 'default checkout location not auto-detected'
# and the same location is accepted when the wrapper points there
mkdir -p "$wrapper_dir"
printf '{ inputs.nixdev-config.url = "path:%s"; outputs = { nixdev-config, ... }: {\n  homeConfigurations.laptop = nixdev-config.lib.mkStandalone { username="you"; homeDirectory="/home/you"; role="laptop"; };\n};\n}\n' "$tmp/home/firstmate/projects/nixdev-config" >"$wrapper_dir/flake.nix"
run --expect-rc 0 -- --dry-run
err_has "checkout: $tmp/home/firstmate/projects/nixdev-config" && pass 'wrapper pointing at default location works' || fail 'wrapper pointing at default location failed'

# -------------------------------------------------------------------- done

echo
if [[ $failed -eq 0 ]]; then
  echo "PASS — $passed regression checks passed (offline, no activation)."
else
  echo "FAIL — $failed of $((passed + failed)) regression checks failed." >&2
  exit 1
fi