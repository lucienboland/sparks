# AGENTS.md — Sparks Repository

Sparks is a standalone AI persona management tool designed as an external
module for the Shellfire framework.

## Structure

```
sparks.bash          Entry point — loaded by shellfire's @module loader
lib/
  core.bash          Persona resolution, merge, sentinel patching
  render.bash        File rendering and sentinel write/remove
  ui.bash            TUI helpers (banner, menu, help)
  doctor.bash        Health checks
  migrate.bash       Migration helpers
adapters/
  opencode.bash      OpenCode (AGENTS.md sentinel)
  claude.bash        Claude Code (CLAUDE.md bootstrap import)
  copilot.bash       GitHub Copilot (.github/copilot-instructions.md)
  gemini.bash        Gemini (GEMINI.md sentinel)
tests/
  test_sparks.bash   Full test suite
```

## Key design points

- `sparks.bash` detects its own path via `BASH_SOURCE[0]` — no dependency on
  shellfire config paths.
- `lib/` sub-modules are lazy-loaded on first use via `_sparks_load_module`.
- Adapters are loaded on demand when an adapter command is dispatched.
- User config lives at `~/.config/sparks/` (XDG-compliant).
- `SPARKS_HOME` env var overrides the install path for development use.

## Testing

```bash
bash ~/code/sparks/tests/test_sparks.bash
```

## Development workflow

```bash
export SPARKS_HOME=~/code/sparks
# Open a new terminal — shellfire loads from SPARKS_HOME automatically
```
