# Claude Code: boundaries for this project

Claude Code is the laptop's **primary coding assistant**. This repository
deliberately does **not** package it as a pinned Nix dependency, so the
native installation and its own update cadence stay authoritative.

## Why not Nix-pinned

- Nix-pinned tools move only when this flake's nixpkgs pin moves (weekly
  Dependabot cadence at best). A *primary* assistant should move on its own
  schedule (hours/days), so the native installer — which auto-updates in
  the background by default — is the right boundary.
- If you ever *want* a floor version, pin `minimumVersion` in Claude Code's
  own settings instead of in Nix.

## Native install (inside the Arch WSL2 distro)

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude --version
claude doctor          # read-only diagnostics
```

- Installs to `~/.local/bin/claude` (symlink into `~/.local/share/claude/`).
- Runs inside WSL2, on the Linux side filesystem (docs/project-placement.md).
- Do **not** `sudo npm`-install Claude Code; the native installer is the
  supported path on WSL.

## Login (WSL2 quirk)

First run opens a browser OAuth flow. On WSL2 the local callback port is
often unreachable, so the documented flow is:

1. `claude` → it prints a login URL.
2. Copy it (`c`), paste into a browser on Windows.
3. Paste the returned code back into the terminal.

Credentials land in `~/.claude/.credentials.json` (mode 0600). `/login`
renews, `/logout` clears. No credential is written by, or needed from, this
repository.

## The credential rules (applies to everything here)

- **Credentials, API keys, OAuth state, and machine-specific assistant
  settings never enter this repository or any Nix file.** Runtime files
  (`~/.claude/`, `~/.pi/agent/`, `~/.ssh/`, `~/.gitconfig`) are the only
  place credentials live, and they are not tracked by the project.
- Watch the environment-variable trap: an ANTHROPIC_API_KEY environment
  variable **overrides** subscription auth in Claude Code and silently
  switches you to per-token API billing. If you use a Pro/Max subscription,
  do not export it. (This doc deliberately shows only the variable name —
  never an example value.)
- Desk-check after any change: `git grep -iE 'sk-ant|ghp_|glpat-|api[_-]?key'`
  should find nothing.

## Model selection

`/model` in an interactive session persists your default model to
`~/.claude/settings.json` (runtime-owned). Aliases: `sonnet` (daily driver),
`opus` (hard reasoning), `haiku` (fast/cheap). `/cost` shows session spend.

## Update boundary

- Native installs **auto-update by default**; that is the intended behavior
  for the primary assistant. Use the `stable` channel via
  `autoUpdatesChannel` if you want calmer releases.
- Tools that *are* Nix-managed (everything in the devShells) follow the
  project rule: never self-update — they move via the flake
  (docs/updates.md). Claude Code is the deliberate exception because it is
  not Nix-managed.

## Removal

```bash
rm -f ~/.local/bin/claude && rm -rf ~/.local/share/claude ~/.claude
```