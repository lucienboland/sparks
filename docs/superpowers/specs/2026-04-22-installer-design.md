# Sparks Installer Design

**Date:** 2026-04-22
**Status:** Approved

---

## Overview

A single `install.sh` script at the repo root provides two capabilities:

1. **Deploy** — copy framework files from the dev clone to the install location
2. **Status** — report the health of the installation and suggest exact fix commands

The install dir (`~/.local/share/sparks`) is **never** a git repo. It is always
populated by `install.sh`. Only the dev clone (`~/code/sparks`) is git-tracked.

This mirrors the approach used in the Shellfire installer (`~/code/shellfire/install.sh`).

---

## Invocation

```
./install.sh            # deploy from dev clone to install dir
./install.sh --status   # print health/drift report
./install.sh --help     # usage summary
```

---

## File Locations

| Path | Purpose |
|------|---------|
| `~/code/sparks/` | Dev clone (git-tracked, source of truth) |
| `~/.local/share/sparks/` | Install dir (never a git repo, always rsync-deployed) |
| `~/.config/sparks/` | User config dir |
| `~/.config/sparks/personas/` | User persona store (user-managed markdown files) |
| `~/.config/sparks/sparks.conf` | Optional sparks config file |
| `~/.config/shellfire/plugins.conf` | Shellfire plugin list — must contain `@sparks` |
| `~/.gemini/settings.json` | Gemini CLI config — must contain `context.fileName` block |
| `~/.local/share/sparks/VERSION` | Stamp file written by installer on every deploy |

---

## Deploy Mode (default)

### Behaviour

1. Determine `SCRIPT_DIR` from `BASH_SOURCE[0]` (the dev clone root)
2. **Safety check:** if `SCRIPT_DIR` resolves to the same path as the install dir, abort
3. Capture `git -C "$SCRIPT_DIR" rev-parse HEAD` as the current commit. If git fails, use `"unknown"` and warn.
4. `rsync -a --delete` the following from dev clone → install dir:
   - `sparks.bash`
   - `lib/`
   - `adapters/`
   - (explicitly excludes: `.git/`, `.gitignore`, `tests/`, `docs/`, `install.sh`, `AGENTS.md`, `README.md`, `INSTALL.md`)
5. Write `VERSION` stamp file to install dir:
   ```
   commit=<git HEAD hash or "unknown">
   deployed_at=<ISO8601 UTC timestamp>
   ```
6. Print a summary of what was deployed
7. Print suggestions for anything missing:
   - `~/.config/sparks/` config scaffold
   - `@sparks` line in `~/.config/shellfire/plugins.conf`
   - `~/.gemini/settings.json` `context.fileName` block

### Safety Properties

- Never modifies any config file — only reads and prints suggestions
- Never touches `~/.config/sparks/` — only checks existence
- Idempotent — safe to re-run
- No interactive prompts

### Output (example)

```
[deploy] source: /Users/lucien/code/sparks (commit: abc1234)
[deploy] target: /Users/lucien/.local/share/sparks
[deploy] syncing framework files...
[deploy] done. VERSION stamp written.

[suggest] ~/.config/sparks not found. To scaffold your config directory:
    mkdir -p ~/.config/sparks/personas
    touch ~/.config/sparks/sparks.conf

[suggest] @sparks not found in ~/.config/shellfire/plugins.conf. Add:
    echo '@sparks' >> ~/.config/shellfire/plugins.conf

[suggest] context.fileName not found in ~/.gemini/settings.json. Add:
    {
      "context": {
        "fileName": ["AGENTS.md", "GEMINI.md"]
      }
    }
```

---

## Status Mode (`--status`)

Runs all checks and prints a health report. Never modifies anything.

### Checks

| Check | Pass | Fail/Warn |
|-------|------|-----------|
| Install dir exists | `[ok]  install dir exists` | `[missing] run: ./install.sh` |
| VERSION stamp present | `[ok]  VERSION stamp present (abc1234)` | `[warn]   run: ./install.sh` |
| Version drift | `[ok]  install is current (abc1234)` | `[drift]  install=abc1234, dev=def5678 — run: ./install.sh` |
| Config dir `~/.config/sparks/` | `[ok]  config dir exists` | `[missing] run: mkdir -p ~/.config/sparks/personas && touch ~/.config/sparks/sparks.conf` |
| Personas dir `~/.config/sparks/personas/` | `[ok]  personas dir exists` | `[missing] run: mkdir -p ~/.config/sparks/personas` |
| `sparks.conf` exists | `[ok]  sparks.conf exists` | `[missing] run: touch ~/.config/sparks/sparks.conf` |
| `@sparks` in `plugins.conf` | `[ok]  @sparks in plugins.conf` | `[missing] run: echo '@sparks' >> ~/.config/shellfire/plugins.conf` |
| `context.fileName` in `~/.gemini/settings.json` | `[ok]  gemini context.fileName configured` | `[missing] <exact JSON snippet>` |

### Version Drift Logic

- Read `commit` field from `~/.local/share/sparks/VERSION`
- Read `git -C "$SCRIPT_DIR" rev-parse HEAD` from the dev clone
- If equal → ok; if different → drift; if VERSION missing → warn; if git fails → warn

### Output Style

- Prefixes: `[ok]`, `[missing]`, `[warn]`, `[drift]`
- No ANSI colours
- Every non-ok line immediately followed by exact fix command
- Exit code: `0` if all checks pass, `1` if any non-ok

---

## What the Installer Does NOT Do

- Does not install itself into `PATH`
- Does not run as root
- Does not modify any config file
- Does not manage persona content (user-managed)
- Does not touch the dev clone
- Install dir is never a git repo

---

## Relationship to Shellfire Installer

Sparks is a Shellfire plugin — it requires Shellfire to be installed and active.
The sparks `--status` check does NOT verify Shellfire's own health (that's
`shellfire/install.sh --status`'s job). However, the `@sparks` in `plugins.conf`
check implicitly verifies the integration point.

---

## Testing

Override env vars for isolated testing:

- `SHELLFIRE_INSTALL_DIR` — overrides `~/.local/share/sparks` (note: same var prefix, different default)
  - Actually use `SPARKS_INSTALL_DIR` to avoid confusion with shellfire
- `SPARKS_INSTALL_DIR` — overrides `~/.local/share/sparks`
- `SPARKS_CONFIG_DIR` — overrides `~/.config/sparks` (already used by sparks.bash itself)
- `SPARKS_PLUGINS_CONF` — overrides `~/.config/shellfire/plugins.conf`
- `SPARKS_GEMINI_SETTINGS` — overrides `~/.gemini/settings.json`

Key test scenarios:
- Deploy to fresh location
- Deploy twice (idempotency)
- Deploy-to-self safety check
- Status with no install
- Status with current install (no drift)
- Status with drifted install
- Status with missing VERSION
- Status with missing config dir
- Status with missing personas dir
- Status with missing sparks.conf
- Status with `@sparks` absent from plugins.conf
- Status with `@sparks` present in plugins.conf
- Status with gemini settings missing entirely
- Status with gemini settings present but missing `context.fileName`
- Status with gemini settings fully configured
- Status with all ok (exit 0)
