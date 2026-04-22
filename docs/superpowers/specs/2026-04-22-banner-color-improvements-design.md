# Banner Color Improvements — Design Spec

## Summary

Two visual improvements to the compact cd banner and the status view in `lib/ui.bash`:

1. **Capitalize and colorize `SPARKS` in the banner** — replace the plain lowercase `sparks:` label with per-letter logo colors (S=pink P=cyan A=lavender R=pink K=cyan S=lavender), matching the large pixel-font logo shown when running `sparks` without arguments.

2. **Highlight `sparks apply` in stale hints** — wherever a stale/not-yet-created hint says `run: sparks apply`, color the `sparks apply` portion in bright logo-cyan (`\033[38;5;51m`) so it stands out from the surrounding yellow text.

## Scope

- **File:** `lib/ui.bash` only
- **Locations changed:**
  - Color definitions block (~line 53): add `_SPARKS_LABEL` variable
  - `_sparks_banner` printf (line 128): use `_SPARKS_LABEL` instead of plain `sparks:`
  - `_sparks_banner` stale_hint (line 123): inline cyan for `sparks apply`
  - `_sparks_status` — 3 printf calls (lines ~285, ~294, ~298): inline cyan for `sparks apply`
- **No other files touched.** Tests do not assert on color escape sequences; no test changes required.

## Color Values Used

| Variable | ANSI | Role |
|---|---|---|
| `_SPARKS_C_LOGO_PINK` | `\033[38;5;201m` | S, R letters |
| `_SPARKS_C_LOGO_CYAN` | `\033[38;5;51m` | P, K letters; `sparks apply` highlight |
| `_SPARKS_C_LOGO_LAVEN` | `\033[38;5;141m` | A, S (second) letters |
| `_SPARKS_C_RESET` | `\033[0m` | Reset after each label |
| `_SPARKS_C_YELLOW` | `\033[38;5;221m` | Surrounding stale hint text (unchanged) |

## New Variable

```bash
_SPARKS_LABEL="${_SPARKS_C_LOGO_PINK}S${_SPARKS_C_LOGO_CYAN}P${_SPARKS_C_LOGO_LAVEN}A${_SPARKS_C_LOGO_PINK}R${_SPARKS_C_LOGO_CYAN}K${_SPARKS_C_LOGO_LAVEN}S${_SPARKS_C_RESET}"
```

## Before / After

**Banner (before):**
```
*.+ sparks: base + dgs  (~/digital/ai/dgs) [stale — run: sparks apply]
      ^^^^^                                                ^^^^^^^^^^^^^
      plain lowercase                                      all yellow
```

**Banner (after):**
```
*.+ SPARKS: base + dgs  (~/digital/ai/dgs) [stale — run: sparks apply]
    ^^^^^^                                                ^^^^^^^^^^^^^
    per-letter logo colors                                cyan
```

## Approved

User-approved 2026-04-22 — design presented inline, user confirmed "this looks right to me."
