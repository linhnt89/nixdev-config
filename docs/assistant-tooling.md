# Assistant tooling: what this repo does and does not provide

Two assistants exist in this design. Their roles, install paths, and
credential boundaries are deliberately different.

## Pi — optional, small/local fallback

- **Role:** optional second assistant, never a default on either machine.
  `nix develop .#assistant` provides the Pi binary on demand.
- **No provider/model shipped.** This repository contains **no** provider
  selection, model pin, or seed settings for Pi — the desktop's
  `~/.pi/agent/settings.json` values (its fleet-wide cloud default) are
  machine-specific and must never be copied here.
- **Local llama.cpp fallback boundary (documented, not required):** when a
  local fallback is wanted, configure it at runtime on the machine:

  ```bash
  pi login llama.cpp        # default router http://127.0.0.1:8080
  # provider/model defaults and LLAMA_BASE_URL land in ~/.pi/agent/ (0600)
  ```

  Nothing about the fallback is required for the base shells — it is an
  opt-in assistant shell, and Pi itself remains optional.
- **Updates:** if installed from this flake (`nix develop .#assistant`),
  it moves with the `nixpkgs-unstable` pin (docs/updates.md) and must not
  self-update. On the laptop, an npm install (`pi update`) is an
  acceptable alternative only if Pi is *not* Nix-managed there — pick one
  boundary per machine and stick to it.

## Claude Code — primary assistant, native install only

Covered in docs/claude-code.md. It is **not** Nix-pinned by design; its
binary, login, auto-updates, and credentials are owned by the native
installer and `~/.claude/`.

## Firstmate — separate repository, private per-machine harness

- Firstmate remains its own private repository; **nothing of it lives in
  this project**: no `data/`, `state/`, `config/`, credentials, or desktop
  dispatch settings are tracked here.
- On the laptop, the Firstmate clone keeps its own gitignored harness
  choice (e.g. `config/crew-harness` set to its primary assistant, a
  Claude-model `crew-dispatch.json`), mirroring how the desktop's
  Pi/deepseek dispatch stays in the desktop's own firstmate home. Which
  harness each machine runs is **private, local state** — this repository
  only documents the boundary, it does not set or record it.
- Firstmate's own toolchain (`fm-bootstrap.sh`, axi CLIs, backend) installs
  without Nix; where this repo's devShells already provide a tool, the
  Nix-managed copy wins on that machine and is never self-updated.

## No-secrets rule (repeated for emphasis)

No credential, API key, OAuth token, provider selection, or machine-specific
assistant setting is accepted in this repository in any form. Runtime state
lives in `~/.claude/`, `~/.pi/agent/`, `~/.ssh/` — mode 0600 when
credential-bearing — and in each machine's private Firstmate home.
`scripts/check.sh` scans for credential-shaped strings on every run.