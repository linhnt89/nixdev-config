# WSL2 prerequisites (laptop only)

The MetaCube desktop already has Nix on NixOS — skip everything here. The
laptop's Arch WSL2 distro needs the following before this repository's
shells work. These are **laptop-local setup steps, not Nix configuration**;
nothing here is managed by this repository.

## Windows side

1. Update WSL itself and confirm the version supports systemd:

   ```powershell
   wsl --update
   wsl --version          # need >= 0.67.6 (systemd support)
   ```

2. Optional but recommended for Nix builds and assistant workloads
   (weights/VRAM aside, builds and node are memory-hungry): raise the WSL VM
   memory cap in `%UserProfile%\.wslconfig`:

   ```ini
   [wsl2]
   memory=12GB
   processors=8
   ```

   Windows is otherwise untouched: no feature toggles, no Windows packages,
   no Windows OpenSSH needed. All development runs inside the distro.

## Inside the Arch distro

3. Ensure the distro boots with systemd. Create/edit `/etc/wsl.conf`
   (owned by the distro — not managed by Nix or this repo):

   ```ini
   [boot]
   systemd=true
   ```

   Then from PowerShell: `wsl --shutdown`, reopen Arch, and verify:

   ```bash
   systemctl is-system-running   # "running" or "degraded", not the no-systemd error
   ```

4. Install Nix (multi-user, since systemd is on — nix.dev's WSL2
   recommendation):

   ```bash
   curl -L https://nixos.org/nix/install | sh -s -- --daemon
   ```

   New shell, then enable the flake commands once (one-time, per-user):

   ```bash
   mkdir -p ~/.config/nix && cat >> ~/.config/nix/nix.conf <<'EOF'
experimental-features = nix-command flakes
EOF
   ```

   This flake also declares `experimental-features` so `nix --accept-flake-config develop` works on machines that have not set nix.conf — but the config-file edit is the robust path (untrusted flakes have their metadata settings ignored otherwise).

   > Alternative routes exist (ArchWiki: `pacman -S nix`, or a single-user
   > `--no-daemon` install) but multi-user is the recommended default;
   > the pacman variant is Arch-version-coupled and single-user lacks the
   > isolation multi-user gives. Whichever route is chosen, systemd must be
   > enabled first.

## Known WSL/Nix caveats

- **Sandbox builds:** Nix builds inside WSL/containers can fail with
  `mounting /proc: Operation not permitted`. The documented mitigation is
  `sandbox = false` in `/etc/nix/nix.conf`. It is a per-distro system file;
  apply it deliberately and only if a build actually fails.
- **Store growth:** the Nix store lives in the distro's ext4 vhdx. It grows
  with every evaluation; prune with `nix store gc` or use `nix-collect-garbage`
  on a schedule once this is in daily use.
- **Keep everything on the Linux side** — see docs/project-placement.md.

## Removal / rollback of the whole setup

```bash
# Nix (multi-user)
rm -rf /nix ~/.nix-profile ~/.local/state/nix ~/.config/nix
sudo systemctl disable --now nix-daemon    # if daemonized
# + remove yourself from the nix-users group if you were added

# /etc/wsl.conf: remove the [boot] systemd block, then wsl --shutdown
```

Windows was never changed, so there is nothing to roll back there.