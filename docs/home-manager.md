# Home Manager integration (Phase 2, not implemented)

Phase 1 ships devShells only. When the laptop experiment proves out, the
portable profile lands here as a **standalone (non-NixOS) Home Manager
output** — never as a NixOS module.

## Shape (design intent, documented so Phase 2 is mechanical)

```nix
# flake.nix additions (Phase 2)
inputs.home-manager.url = "github:nix-community/home-manager/release-26.05";
inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

# outputs.homeConfigurations."<user>@laptop" = home-manager.lib.homeManagerConfiguration {
#   pkgs = nixpkgs.legacyPackages.x86_64-linux;   # same stable pin
#   modules = [
#     { home.username = "<user>"; home.homeDirectory = "/home/<user>"; }
#     ({ pkgs, ... }: { home.packages = laptopPackages pkgs; })   # role split preserved
#     ./home/modules/shell.nix      # portable subset only
#     ./home/modules/git.nix        # identity values stay OUT of Nix
#     ./home/modules/dev.nix        # direnv/nix-direnv, lazygit, CLI utils
#   ];
# };
```

**Parameterized, never hard-coded:** username, home directory, and role are
arguments — the same profile must be able to target a differently-named
user home (the laptop username is not guaranteed to be `linhnt`) without
editing module files. The package lists in `flake.nix` are the single
source of truth the profile imports.

## Activation (laptop)

```bash
nix run .#homeConfigurations."<user>@laptop".activationPackage
# or, with the standalone home-manager CLI:
home-manager switch --flake .#"<user>@laptop"
```

Requires WSL systemd running ([boot] systemd=true) — HM's `systemd.user`
units silently degrade without it. Rollback becomes generation-based:
`home-manager generations` / `home-manager rollback`.

## In scope (portable only)

- Shell (zsh, starship, fzf integration), Git/delta/SSH *client* settings
  (structure only — identity values are local user data), development
  tools, direnv/nix-direnv, optional assistant tooling.

## Out of scope, permanently

- Any NixOS module: system services, users/groups, `/etc`, boot, hardware,
  networking, firewalls, sshd. The distro (`/etc/wsl.conf`, `pacman`) and
  Windows (`.wslconfig`, WSL features) stay exactly as documented.
- GUI/desktop/Hyprland/audio/Bluetooth/portal configuration — there is no
  analogue on a headless WSL dev box, and the desktop's live in the
  nixos-config repository, not this one.
- Hard-coded assistant defaults: the profile may provide Pi's *seed files*
  only if they are portable defaults (e.g. local llama.cpp provider) with
  no provider key or model pinned to a machine (docs/assistant-tooling.md).

## Role split in the profile

`<user>@laptop` → glab; any future `<user>@desktop` output would remain
`gh`-role and is not required — the desktop keeps its existing NixOS
configuration and consumes this project through the `desktop` devShell.