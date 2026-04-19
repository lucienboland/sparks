# Gemini CLI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Gemini CLI into sparks' existing AGENTS.md infrastructure via a one-time `settings.json` config, and document both integration modes in the sparks repo.

**Architecture:** Gemini CLI's `context.fileName` setting makes it search for `AGENTS.md` (already written by the opencode adapter) in every project — no per-project GEMINI.md needed. The existing `adapters/gemini.bash` sentinel approach is documented as the fallback for Gemini-only projects. The global `~/.gemini/settings.json` is managed by chezmoi alongside other dotfiles.

**Tech Stack:** bash, JSON, chezmoi, Gemini CLI (`~/.gemini/settings.json`)

---

### Task 1: Write spec document to sparks repo

**Files:**
- Create: `docs/superpowers/specs/2026-04-20-gemini-integration-design.md`

- [ ] **Step 1: Write spec file**

Content (write verbatim):

```markdown
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
(oauth_creds.json, history/, tmp/, state.json, trustedFolders.json) are NOT
tracked — they are runtime/secret data.

### 2. `adapters/gemini.bash` (sparks repo)

Replace the thin header comment with a documentation block explaining both
integration modes. Function bodies are unchanged.

### 3. `INSTALL.md` (sparks repo)

Add a "Gemini CLI" section with one-time setup steps for the settings.json
approach.

### 4. `README.md` (sparks repo)

Add Gemini CLI to the supported tools section.

## What Is NOT Changed

- No core sparks code (`lib/`, `sparks.bash`)
- No adapter logic
- No new tests
- `SPARKS_ACTIVE_ADAPTERS` defaults stay as `(opencode claude)`
```

- [ ] **Step 2: Commit spec**

```bash
cd ~/code/sparks
git add docs/superpowers/specs/2026-04-20-gemini-integration-design.md
git commit -m "docs: add Gemini CLI integration design spec"
```

---

### Task 2: Update `~/.gemini/settings.json` and track with chezmoi

**Files:**
- Modify: `~/.gemini/settings.json`
- Create: `~/.local/share/chezmoi/dot_gemini/settings.json` (via chezmoi add)

- [ ] **Step 1: Update `~/.gemini/settings.json`**

Replace content with (preserving existing `security.auth` block):

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

- [ ] **Step 2: Add to chezmoi**

```bash
chezmoi add ~/.gemini/settings.json
```

Expected: creates `~/.local/share/chezmoi/dot_gemini/settings.json` with no output.

- [ ] **Step 3: Verify chezmoi source**

```bash
cat ~/.local/share/chezmoi/dot_gemini/settings.json
```

Expected: the JSON above (with both `security` and `context` blocks).

- [ ] **Step 4: Commit and push dotfiles**

```bash
cd ~/.local/share/chezmoi
git add dot_gemini/settings.json
git commit -m "feat: configure Gemini CLI to load AGENTS.md as context file"
git push
```

Expected: push to `lucienboland/dotfiles` succeeds.

---

### Task 3: Update `adapters/gemini.bash` header

**Files:**
- Modify: `adapters/gemini.bash`

- [ ] **Step 1: Replace header comment**

Replace the top of the file with:

```bash
#!/usr/bin/env bash
# =============================================================================
# adapters/gemini.bash — Gemini CLI adapter
#
# Gemini CLI integration — two approaches:
#
# RECOMMENDED — settings.json (for users who also use OpenCode):
#   Configure ~/.gemini/settings.json so Gemini picks up AGENTS.md (written
#   by the opencode adapter) natively in every project. No per-project
#   GEMINI.md needed; always in sync without running sparks apply.
#
#   Add to ~/.gemini/settings.json:
#     {
#       "context": {
#         "fileName": ["AGENTS.md", "GEMINI.md"]
#       }
#     }
#
#   See INSTALL.md § "Gemini CLI" for the full one-time setup steps.
#
# FALLBACK — direct sentinel (Gemini-only projects, no AGENTS.md):
#   Add "gemini" to SPARKS_ACTIVE_ADAPTERS in ~/.config/sparks/sparks.conf:
#     SPARKS_ACTIVE_ADAPTERS=(opencode claude gemini)
#
#   Then run:  sparks apply
#   This writes persona content directly into GEMINI.md via the sentinel
#   protocol. Run sparks doctor to check for staleness.
# =============================================================================
```

Keep the three function bodies (`_sparks_adapter_gemini_file`,
`_sparks_adapter_gemini_apply`, `_sparks_adapter_gemini_remove`) unchanged.

- [ ] **Step 2: Verify bash syntax**

```bash
bash -n adapters/gemini.bash
```

Expected: no output (syntax OK).

---

### Task 4: Update `INSTALL.md` — add Gemini CLI section

**Files:**
- Modify: `INSTALL.md`

- [ ] **Step 1: Append Gemini CLI section**

Add after the existing "Updating" section:

```markdown
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
```

---

### Task 5: Update `README.md` — add Gemini to supported tools

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add supported tools section**

After the "Usage" section and before "Development", add:

```markdown
## Supported AI tools

| Tool | Context file | Sync mechanism |
|------|-------------|----------------|
| OpenCode | `AGENTS.md` | Sentinel block (direct content) |
| Claude Code | `CLAUDE.md` | Bootstrap: `@AGENTS.md` import |
| GitHub Copilot | `.github/copilot-instructions.md` | Sentinel block |
| Gemini CLI | `AGENTS.md` (via settings.json) | Native file discovery |
| Gemini CLI (standalone) | `GEMINI.md` | Sentinel block |

See `INSTALL.md` for Gemini CLI one-time setup.
```

---

### Task 6: Commit and push sparks repo

**Files:** all modified files above

- [ ] **Step 1: Commit all sparks changes**

```bash
cd ~/code/sparks
git add adapters/gemini.bash INSTALL.md README.md \
        docs/superpowers/plans/2026-04-20-gemini-integration.md
git commit -m "feat: document Gemini CLI integration via settings.json context.fileName"
```

- [ ] **Step 2: Push**

```bash
git push
```

Expected: pushes to origin successfully.
