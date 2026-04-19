# Gemini CLI Integration — Design Spec
Date: 2026-04-20

## Summary

Gemini CLI supports a `context.fileName` setting in `~/.gemini/settings.json`
that instructs it to search for named context files (e.g. `AGENTS.md`) in the
project hierarchy — the same file sparks writes via the opencode adapter.
Rather than duplicating content into a separate `GEMINI.md`, Gemini is
configured to read `AGENTS.md` natively. This is a one-time global config
change, not per-project work.

The existing `adapters/gemini.bash` (direct sentinel to GEMINI.md) is
documented as the fallback for Gemini-only projects where no AGENTS.md exists.

## Changes

### 1. `~/.gemini/settings.json` (dotfiles / chezmoi)

Merge `context.fileName` into the existing settings, preserving `security.auth`:

```json
{
  "security": {
    "auth": {
      "selectedType": "oauth-personal"
    }
  },
  "context": {
    "fileName": ["AGENTS.md", "GEMINI.md"]
  }
}
```

Tracked in chezmoi as `dot_gemini/settings.json`. Other `~/.gemini/` files
(`oauth_creds.json`, `history/`, `tmp/`, `state.json`, `trustedFolders.json`)
are NOT tracked — they are runtime/secret data.

### 2. `adapters/gemini.bash` (sparks repo)

Replace the thin header comment with a documentation block explaining both
integration modes. Function bodies are unchanged.

### 3. `INSTALL.md` (sparks repo)

Add a "Gemini CLI" section with one-time setup steps for the settings.json
approach.

### 4. `README.md` (sparks repo)

Add a supported tools table showing all four adapters plus the Gemini
settings.json approach.

## What Is NOT Changed

- No core sparks code (`lib/`, `sparks.bash`)
- No adapter logic
- No new tests
- `SPARKS_ACTIVE_ADAPTERS` defaults stay as `(opencode claude)`
- `gemini` adapter remains opt-in via `sparks.conf`
