# lib/firstmate.nix — single source of truth for the optional Firstmate
# toolchain.
#
# Imported by flake.nix (the `firstmate` devShell) and by the portable Home
# Manager module home/modules/firstmate.nix, so the ephemeral shell and the
# persistent profile install the exact same tools. This mirrors the
# lib/package-lists.nix role; it lives in its own file because the Firstmate
# set is not expressible as a plain `pkgs: [ ... ]` list: the axi CLIs need an
# npm lockfile root (firstmate/node-tools) and the treehouse/no-mistakes/herdr
# binaries come from pinned external sources (docs/firstmate.md).
#
# What is installed (the verified default/reference workflow = the tmux
# backend; docs/firstmate.md):
#   - universal Firstmate toolchain: node, git, gh, jq, the five axi CLIs,
#     no-mistakes;
#   - the tmux backend's session CLI plus the treehouse worktree provider.
# The optional Herdr backend binary is NOT installed by default — enable it
# per profile with `nixdev.firstmate.enableHerdr` (pinned herdr release asset).
#
# Nothing here carries identity, credentials, remotes, provider/model
# settings, or Firstmate source/state — this repo installs tools only.
{ pkgs, treehousePkg }:

let
  # Shared Node: the same `pkgs.nodejs` the common package set and the role
  # profiles use. Pinning a separate node here would collide with the profile's
  # node at Home Manager generation time (same reasoning as the desktop's
  # firstmate module); Firstmate's own bootstrap works against any modern
  # node, so one shared Node is the right boundary.
  nodejs = pkgs.nodejs;

  # The five pinned axi CLIs, installed from firstmate/node-tools (package.json
  # + package-lock.json) via nixpkgs' npm lock importer. Versions are exact and
  # deliberately bumped (docs/firstmate.md); the archived node_modules are
  # immutable in the Nix store and never self-update.
  nodeModules =
    pkgs.importNpmLock.buildNodeModules {
      npmRoot = ../firstmate/node-tools;
      inherit nodejs;
    };

  # Wrappers exposing the five axi CLIs on PATH, with node_modules/.bin and
  # node on PATH because they exec one another and the node runtime.
  axiTools =
    pkgs.runCommand "firstmate-node-tools"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p "$out/bin"

        for tool in \
          gh-axi \
          chrome-devtools-axi \
          lavish-axi \
          tasks-axi \
          quota-axi
        do
          makeWrapper \
            "${nodeModules}/node_modules/.bin/$tool" \
            "$out/bin/$tool" \
            --prefix PATH : \
              "${nodeModules}/node_modules/.bin:${pkgs.lib.makeBinPath [ nodejs ]}"
        done
      '';

  # ---- Pinned non-nixpkgs binaries -------------------------------------
  # Each entry mirrors the asset Firstmate's own installer would fetch
  # (docs/firstmate.md), pinned here by exact URL + SRI hash so the Nix build
  # is reproducible and the binary is verifiable. Update boundary: docs/
  # updates.md — these only move when this file's pins are deliberately
  # bumped, never by the tools themselves.

  # Per-system release assets (linux only; this repo's devShells and the HM
  # profiles target Linux). HM profiles are x86_64-linux; the firstmate
  # devShell additionally covers aarch64-linux.
  assets = {
    x86_64-linux = {
      noMistakes = {
        url = "https://github.com/kunchenguid/no-mistakes/releases/download/v1.46.0/no-mistakes-v1.46.0-linux-amd64.tar.gz";
        hash = "sha256-OM08M1Z5HxSpNjE5r8UtJA003OOD9HTgyKN7c9X/05U=";
      };
      herdr = {
        url = "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-linux-x86_64";
        hash = "sha256-uHLqfkD6LLF+hXrJtisb8m23tAPGIvXS8/WzX26azSg=";
      };
    };
    aarch64-linux = {
      noMistakes = {
        url = "https://github.com/kunchenguid/no-mistakes/releases/download/v1.46.0/no-mistakes-v1.46.0-linux-arm64.tar.gz";
        hash = "sha256-/9j/Xh4Whh5oO7RHqKYysDxZUEjXCftYwb28BihUpAo=";
      };
      herdr = {
        url = "https://github.com/herdrdev/herdr/releases/download/v0.8.0/herdr-linux-aarch64";
        hash = "sha256-9kesZkaNnvvGQv5TT7KERo8K6mBkFgb8AI38DYKjyoc=";
      };
    };
  };

  asset =
    assets.${pkgs.system}
      or (throw
        "nixdev-config: Firstmate tools are not pinned for system '${pkgs.system}' (supported: x86_64-linux, aarch64-linux)");

  # no-mistakes: statically linked release binary (> = 1.31.2 required by the
  # Firstmate bootstrap; this pin is 1.46.0). Runs as-is from the Nix store on
  # both machines. The archive contains a bare `no-mistakes` file, hence
  # dontUnpack + explicit extraction.
  noMistakes =
    pkgs.stdenv.mkDerivation {
      pname = "no-mistakes";
      version = "1.46.0";

      src = pkgs.fetchurl {
        url = asset.noMistakes.url;
        sha256 = asset.noMistakes.hash;
      };

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = false;
      doStrip = false; # prebuilt; strip might hurt static x86_64 binaries

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        tar -xzf "$src" -C "$out/bin"
        chmod 0755 "$out/bin/no-mistakes"
        runHook postInstall
      '';

      meta = {
        description = "Firstmate's validation pipeline (pinned release binary)";
        license = pkgs.lib.licenses.mit; # MIT (see upstream kunchenguid/no-mistakes)
        platforms = [ pkgs.system ];
      };
    };

  # treehouse: the worktree provider for the tmux (and herdr) backend. Pinned
  # to the upstream flake at tag v2.1.1 (Go source build — patched for NixOS,
  # unlike the raw release archive which is glibc-dynamic and would not run on
  # the MetaCube NixOS PC without nix-ld; the desktop's nixos-config uses the
  # same flake). The flake input itself is pinned in flake.lock.
  treehouse = treehousePkg;

  # herdr: OPTIONAL session-provider CLI (only installed when
  # `nixdev.firstmate.enableHerdr` is set). Statically linked release binary
  # (v0.8.0, the version the desktop's nixos-config already runs). This repo
  # installs the binary only — it never starts, stops, or drives Herdr.
  herdr =
    pkgs.stdenv.mkDerivation {
      pname = "herdr";
      version = "0.8.0";

      src = pkgs.fetchurl {
        url = asset.herdr.url;
        sha256 = asset.herdr.hash;
      };

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      dontFixup = false;
      doStrip = false;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out/bin"
        install -Dm755 "$src" "$out/bin/herdr"
        runHook postInstall
      '';

      meta = {
        description = "Herdr terminal workspace manager (pinned release binary, opt-in)";
        license = pkgs.lib.licenses.asl20; # Apache-2.0 (see upstream herdrdev/herdr)
        platforms = [ pkgs.system ];
      };
    };
in
{
  inherit
    nodejs
    axiTools
    noMistakes
    treehouse
    herdr
    ;

  # The default toolchain for the Firstmate reference workflow (tmux
  # backend). `gh` is included because Firstmate currently requires it — this
  # is the explicit opt-in that may add `gh` to a laptop profile that would
  # otherwise stay glab-only (docs/firstmate.md). By default the non-Firstmate
  # laptop/desktop profiles keep their role split unchanged.
  packages = [
    nodejs
    pkgs.gitFull
    pkgs.tmux
    pkgs.jq
    pkgs.gh
    axiTools
    noMistakes
    treehouse
  ];

  banner = ''
    __ nixdev-config — optional Firstmate toolchain (tmux backend) __________
      Universal tools : node, git, gh, jq, gh-axi, chrome-devtools-axi,
                        lavish-axi, tasks-axi, quota-axi, no-mistakes
      Session/works   : tmux (default backend) + treehouse
      Herdr backend   : opt-in per profile (nixdev.firstmate.enableHerdr)
      Creds/state     : never here — gh auth, ~/.ssh, ~/.claude, and the
                        separate firstmate home stay machine-local.
      Docs            : docs/firstmate.md
      ______________________________________________________________________
  '';
}