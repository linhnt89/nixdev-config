# Git workflows per role

The role split in this repository exists so the two machines never install
the same Git hosting CLI merely because the base environment is shared.

## Laptop (Arch WSL2 work machine) — company GitLab is home

- **Push/pull destination: company GitLab.** The laptop shell ships
  `glab` (`nix develop` / `devShells.laptop`).
- **Setup (local only, never in Nix):**

  ```bash
  # identity — your data, your machine
  git config --global user.name  "Your Name"
  git config --global user.email "you@company.example"

  # authentication
  ssh-keygen -t ed25519 -C "you@company.example"          # -> ~/.ssh
  glab auth login                                          # or add the SSH key in GitLab UI

  # credentials live in ~/.ssh and glab's own storage; nothing goes in Nix.
  ```

- Remotes are configured per checkout: `git remote add origin
  git@gitlab.com:team/project.git` (or `glab repo clone`). Keep SSH keys in
  `~/.ssh`; `programs.ssh`-style config is a Phase 2 Home Manager concern
  (docs/home-manager.md), deliberately not in this flake.

### GitHub on the laptop: read-only, optional, on demand

- Public GitHub sources are pulled read-only (`git clone https://...`).
- `gh` is **not** part of the laptop shell. When you need it temporarily:

  ```bash
  nix shell nixpkgs#gh       # ephemeral, read-only use for external sources
  ```

- No GitHub credentials are required for public pulls; if you ever need to
  *push* to GitHub from the laptop, that is a deliberate decision (separate
  SSH key / identity), not a default here.

## Desktop (MetaCube NixOS) — GitHub is home

- The desktop shell ships `gh` (`nix develop .#desktop`); the desktop's
  personal pushes go to GitHub, authenticated via `gh auth login` (SSH)
  and its existing `~/.ssh` setup — all local, unchanged by this repo.
- GitLab is not installed on the desktop; `glab` is available on demand via
  `nix shell nixpkgs#glab` if ever needed (not a default).

## Shared rules

- **Nothing credential-shaped belongs in Nix.** No `git config`, no remote
  URLs, no tokens, no `~/.ssh` content — `scripts/check.sh` enforces this
  on the repo side; machines keep their own local git config.
- SSH agent handling (`SSH_AUTH_SOCK`) is machine-local; the desktop's
  mechanism comes from its own configuration, the laptop's from its distro
  setup. Neither is reproduced here.