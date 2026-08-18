# Project placement: WSL filesystem, not /mnt/c

## The rule

On the laptop, **all files worked on by WSL-side tools — project checkouts,
this repository, Git data, the Nix store — live in the Arch distro's ext4
filesystem** (e.g. `~/firstmate/projects`). Never under `/mnt/c`.

`/mnt/c` is a DrvFS (9p) network mount. Working across it is slow for git,
file watching, and builds, and it breaks editor/tool file-watching by design
(Windows mounts don't propagate Linux inotify correctly).

## Concretely

```bash
mkdir -p ~/firstmate/projects
git clone git@gitlab.com:you/project.git ~/firstmate/projects/project
git clone https://github.com/linhnt89/nixdev-config ~/firstmate/projects/nixdev-config   # read-only pull on the laptop
cd ~/firstmate/projects/nixdev-config && nix develop
```

The nixdev-config checkout and the standalone Home Manager wrapper
(defaults `~/firstmate/projects/nixdev-config` and
`~/.config/home-manager`) are exactly what the companion update lane
`scripts/update-home-manager.sh` works on — docs/home-manager.md.

- Windows-side access to these files is **viewing only**, via
  `\\wsl$\Arch\home\<user>\projects\...` (or `explorer.exe .` from inside
  WSL while interop is enabled — leave `[interop]` enabled; Claude Code's
  sandbox and login flow assume it).
- Edit from Windows when you must? Use **VS Code with the Remote - WSL
  extension**, which talks to the distro directly — it does not touch
  `/mnt/c`. Never point a Windows editor at `\\wsl$` paths as a workflow.
- `.wslconfig` memory/CPU limits (docs/wsl2-prerequisites.md) affect how
  fast Nix builds and assistants run; that is Windows-side tuning.

## Why it matters for this repository

`nix develop` builds into the Nix store in the distro's ext4. Clone this
repo into `~/projects` (or wherever your Linux-side code lives) — a clone
under `/mnt/c` would evaluate fine but build slowly and watch files badly.