# Banner Color Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capitalize and per-letter-colorize `SPARKS` in the cd banner, and highlight `sparks apply` in cyan wherever stale hints appear.

**Architecture:** Single file edit to `lib/ui.bash` — add one new color variable, update one printf call in `_sparks_banner`, update the stale_hint string, update three printf calls in `_sparks_status`.

**Tech Stack:** Bash, ANSI escape codes

---

### Task 1: Add `_SPARKS_LABEL` variable and update banner printf + stale_hint

**Files:**
- Modify: `lib/ui.bash`

- [ ] **Step 1: Add `_SPARKS_LABEL` after the `_SPARKS_ICON` line (~line 53)**

In `lib/ui.bash`, find:
```bash
# The spark icon — *.+ with logo triad colours (compact, for inline banner use)
_SPARKS_ICON="${_SPARKS_C_LOGO_PINK}*${_SPARKS_C_LOGO_CYAN}.${_SPARKS_C_LOGO_LAVEN}+${_SPARKS_C_RESET}"
```

Add after it:
```bash
# Per-letter colored SPARKS label for banner (S=pink P=cyan A=lav R=pink K=cyan S=lav)
_SPARKS_LABEL="${_SPARKS_C_LOGO_PINK}S${_SPARKS_C_LOGO_CYAN}P${_SPARKS_C_LOGO_LAVEN}A${_SPARKS_C_LOGO_PINK}R${_SPARKS_C_LOGO_CYAN}K${_SPARKS_C_LOGO_LAVEN}S${_SPARKS_C_RESET}"
```

- [ ] **Step 2: Update stale_hint in `_sparks_banner` (~line 123)**

Find:
```bash
        stale_hint=" ${_SPARKS_C_YELLOW}[stale — run: sparks apply]${_SPARKS_C_RESET}"
```

Replace with:
```bash
        stale_hint=" ${_SPARKS_C_YELLOW}[stale — run: ${_SPARKS_C_LOGO_CYAN}sparks apply${_SPARKS_C_YELLOW}]${_SPARKS_C_RESET}"
```

- [ ] **Step 3: Update banner printf (~line 128)**

Find:
```bash
  printf '%b sparks: %s  %s%s\n' \
    "${_SPARKS_ICON}" "${persona_str}" "${source_hint}" "${stale_hint}"
```

Replace with:
```bash
  printf '%b %b: %s  %s%s\n' \
    "${_SPARKS_ICON}" "${_SPARKS_LABEL}" "${persona_str}" "${source_hint}" "${stale_hint}"
```

- [ ] **Step 4: Run the test suite to confirm no regressions**

```bash
bash ~/code/sparks/tests/test_sparks.bash
```

Expected: all tests pass (currently 108 tests).

- [ ] **Step 5: Commit**

```bash
git -C ~/code/sparks add lib/ui.bash docs/superpowers/specs/2026-04-22-banner-color-improvements-design.md docs/superpowers/plans/2026-04-22-banner-color-improvements.md
git -C ~/code/sparks commit -m "feat: capitalize and colorize SPARKS label in cd banner"
```

---

### Task 2: Highlight `sparks apply` in `_sparks_status`

**Files:**
- Modify: `lib/ui.bash`

- [ ] **Step 1: Update "not yet created" printf (~line 285)**

Find:
```bash
          printf '    %b○%b  %-38s  %b[not yet created — run: sparks apply]%b\n' \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}" \
            "${display_path}" \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}"
```

Replace with:
```bash
          printf '    %b○%b  %-38s  %b[not yet created — run: %bsparks apply%b]%b\n' \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}" \
            "${display_path}" \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}"
```

- [ ] **Step 2: Update "not set up" printf (~line 294)**

Find:
```bash
            printf '    %b!%b  %-38s  %b[not set up — run: sparks apply]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
```

Replace with:
```bash
            printf '    %b!%b  %-38s  %b[not set up — run: %bsparks apply%b]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
```

- [ ] **Step 3: Update "stale" printf (~line 298)**

Find:
```bash
            printf '    %b!%b  %-38s  %b[stale — run: sparks apply]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
```

Replace with:
```bash
            printf '    %b!%b  %-38s  %b[stale — run: %bsparks apply%b]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
```

- [ ] **Step 4: Run tests**

```bash
bash ~/code/sparks/tests/test_sparks.bash
```

Expected: all tests pass.

- [ ] **Step 5: Commit and push**

```bash
git -C ~/code/sparks add lib/ui.bash
git -C ~/code/sparks commit -m "feat: highlight 'sparks apply' in cyan in all stale hints"
git -C ~/code/sparks push
```
