# Installing Sparks

## Requirements

- [Shellfire](https://github.com/lucienboland/shellfire) with `@module` loader support

## Installation

```bash
git clone git@github.com:lucienboland/sparks.git ~/.local/share/sparks
```

Add `@sparks` to `~/.config/shellfire/plugins.conf` and open a new terminal.

## Updating

```bash
cd ~/.local/share/sparks && git pull
```

## Gemini CLI integration

Gemini CLI can read `AGENTS.md` directly — no separate `GEMINI.md` needed.
One-time setup: add `context.fileName` to `~/.gemini/settings.json`.

If `~/.gemini/settings.json` does not exist yet, create it:

```json
{
  "context": {
    "fileName": ["AGENTS.md", "GEMINI.md"]
  }
}
```

If it already exists, merge in the `context` block (preserve any existing
keys such as `security.auth`).

After this change, any project where `sparks apply` has written `AGENTS.md`
(via the opencode adapter) will automatically provide persona context to
Gemini CLI sessions — no extra steps required.

**Alternative (Gemini-only projects):** If a project does not use OpenCode and
has no `AGENTS.md`, enable the gemini adapter instead:

```bash
# In ~/.config/sparks/sparks.conf:
SPARKS_ACTIVE_ADAPTERS=(opencode claude gemini)
```

Then run `sparks apply` in the project. Gemini will read `GEMINI.md`
directly. Run `sparks doctor` to check for staleness.
