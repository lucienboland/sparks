# Sparks

AI persona manager for [Shellfire](https://github.com/lucienboland/shellfire).

Sparks manages context files (`AGENTS.md`, `CLAUDE.md`, etc.) across project
directories using a directory-inheritance model. Personas are stored centrally
in `~/.config/sparks/personas/` and activated per-directory via `.sparks` files.

## Quick start

Install:

```bash
git clone git@github.com:lucienboland/sparks.git ~/.local/share/sparks
```

Add to `~/.config/shellfire/plugins.conf`:

```
@sparks
```

Open a new terminal.

## Usage

```
sparks on <persona>     Activate a persona in the current directory
sparks apply            Write AI context files for active personas
sparks status           Show current persona state
sparks list             List available personas
sparks help             Full command reference
```

## Supported AI tools

| Tool | Context file | Sync mechanism |
|------|-------------|----------------|
| OpenCode | `AGENTS.md` | Sentinel block (direct content) |
| Claude Code | `CLAUDE.md` | Bootstrap: `@AGENTS.md` import |
| GitHub Copilot | `.github/copilot-instructions.md` | Sentinel block |
| Gemini CLI | `AGENTS.md` (via settings.json) | Native file discovery |
| Gemini CLI (standalone) | `GEMINI.md` | Sentinel block |

See `INSTALL.md` for Gemini CLI one-time setup.

## Development

```bash
export SPARKS_HOME=~/code/sparks
# Open a new terminal — shellfire picks up SPARKS_HOME automatically
```

## Testing

```bash
bash ~/code/sparks/tests/test_sparks.bash
```
