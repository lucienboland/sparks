# Sparks Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `install.sh` for the Sparks AI persona manager — a single script that deploys the framework from the dev clone to the install location and reports health/drift status.

**Architecture:** Single bash script at repo root with two modes: deploy (default) and `--status`. Mirrors the shellfire installer exactly in structure and philosophy. Version drift tracked via a `VERSION` stamp file. Install dir is never a git repo. Five status checks beyond version: config dir, personas dir, sparks.conf, @sparks in plugins.conf, and gemini context.fileName.

**Tech Stack:** Bash (must work on macOS bash 3.2), rsync, git (read-only, dev clone only)

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `install.sh` | Create | Main installer script |
| `tests/test_installer.bash` | Create | Test suite for installer |
| `docs/superpowers/specs/2026-04-22-installer-design.md` | Already written | Spec (reference) |

### Override env vars used throughout

| Var | Default | Purpose |
|-----|---------|---------|
| `SPARKS_INSTALL_DIR` | `~/.local/share/sparks` | Install location |
| `SPARKS_CONFIG_DIR` | `~/.config/sparks` | User config dir (also used by sparks.bash itself) |
| `SPARKS_PLUGINS_CONF` | `~/.config/shellfire/plugins.conf` | Shellfire plugins.conf |
| `SPARKS_GEMINI_SETTINGS` | `~/.gemini/settings.json` | Gemini CLI settings |

---

### Task 1: Test harness scaffold

**Files:**
- Create: `tests/test_installer.bash`

- [ ] **Step 1: Create the test file with harness**

```bash
#!/usr/bin/env bash
# =============================================================================
# test_installer.bash -- Tests for install.sh (Sparks)
# =============================================================================
# Usage:
#   bash tests/test_installer.bash           # all tests
#   bash tests/test_installer.bash -s deploy # one section
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALLER="${REPO_DIR}/install.sh"

# ---------------------------------------------------------------------------
# Minimal test framework (intentionally simpler than test_sparks.bash)
# ---------------------------------------------------------------------------
_pass_count=0
_fail_count=0
_section_name=""

_section() { _section_name="$1"; echo; echo "=== $1 ==="; }
_ok()      { _pass_count=$(( _pass_count + 1 )); echo "  ok: $*"; }
_fail()    { _fail_count=$(( _fail_count + 1 )); echo "  FAIL: $*"; }
_assert()  { local desc="$1" actual="$2" expected="$3"
             if [[ "$actual" == "$expected" ]]; then _ok "$desc"
             else _fail "$desc — got: '$actual' expected: '$expected'"; fi; }
_assert_contains() { local desc="$1" haystack="$2" needle="$3"
             if [[ "$haystack" == *"$needle"* ]]; then _ok "$desc"
             else _fail "$desc — '$needle' not found in output"; fi; }
_assert_exit() { local desc="$1" actual="$2" expected="$3"
             if [[ "$actual" == "$expected" ]]; then _ok "$desc"
             else _fail "$desc — exit code: got $actual, expected $expected"; fi; }

_summary() {
  echo
  echo "Results: ${_pass_count} passed, ${_fail_count} failed"
  [[ "$_fail_count" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Section filter (-s <name>)
# ---------------------------------------------------------------------------
_run_section="${2-}"
if [[ "${1-}" == "-s" ]]; then _run_section="${2-}"; fi
_should_run() { [[ -z "$_run_section" || "$_run_section" == "$1" ]]; }

# ---------------------------------------------------------------------------
# Temp environment helper
# _make_tmpenv: creates isolated dirs, exports override vars, sets _TMPENV_ROOT
# _cleanup_tmpenv: removes temp dir and unsets all override vars
# ---------------------------------------------------------------------------
_TMPENV_ROOT=""

_make_tmpenv() {
  local tmp
  tmp="$(mktemp -d)"
  _TMPENV_ROOT="$tmp"
  export SPARKS_INSTALL_DIR="${tmp}/install"
  export SPARKS_CONFIG_DIR="${tmp}/config"
  export SPARKS_PLUGINS_CONF="${tmp}/plugins.conf"
  export SPARKS_GEMINI_SETTINGS="${tmp}/gemini_settings.json"
}

_cleanup_tmpenv() {
  rm -rf "$_TMPENV_ROOT"
  unset SPARKS_INSTALL_DIR SPARKS_CONFIG_DIR SPARKS_PLUGINS_CONF SPARKS_GEMINI_SETTINGS _TMPENV_ROOT
}
```

Then add `_summary` as the very last line of the file.

- [ ] **Step 2: Run to verify zero errors**

```bash
bash tests/test_installer.bash
```

Expected: `Results: 0 passed, 0 failed`

- [ ] **Step 3: Commit**

```bash
git add tests/test_installer.bash
git commit -m "test: add installer test harness scaffold"
```

---

### Task 2: Create `install.sh` skeleton with `--help` and `_get_dev_commit`

**Files:**
- Create: `install.sh`
- Modify: `tests/test_installer.bash`

- [ ] **Step 1: Add `--help` and commit detection tests to `tests/test_installer.bash`**

Add both blocks before `_summary`:

```bash
_should_run "help" && {
  _section "help"

  _make_tmpenv
  output="$(bash "$INSTALLER" --help 2>&1)"
  exit_code=$?
  _assert_exit "--help exits 0" "$exit_code" "0"
  _assert_contains "--help mentions usage" "$output" "Usage:"
  _assert_contains "--help mentions --status" "$output" "--status"
  _cleanup_tmpenv
}

_should_run "commit" && {
  _section "commit detection"

  _make_tmpenv
  commit="$(
    SPARKS_INSTALL_DIR="${SPARKS_INSTALL_DIR}"
    SPARKS_CONFIG_DIR="${SPARKS_CONFIG_DIR}"
    SPARKS_PLUGINS_CONF="${SPARKS_PLUGINS_CONF}"
    SPARKS_GEMINI_SETTINGS="${SPARKS_GEMINI_SETTINGS}"
    bash -c "source '$INSTALLER' --_source-only 2>/dev/null; _get_dev_commit" 2>/dev/null
  )"
  if [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || [[ "$commit" == "unknown" ]]; then
    _ok "commit is valid hex or unknown: $commit"
  else
    _fail "commit has unexpected format: '$commit'"
  fi
  _cleanup_tmpenv
}
```

- [ ] **Step 2: Run to verify both sections fail**

```bash
bash tests/test_installer.bash -s help
bash tests/test_installer.bash -s commit
```

Expected: FAILs (install.sh doesn't exist yet)

- [ ] **Step 3: Create `install.sh`**

```bash
#!/usr/bin/env bash
# =============================================================================
# install.sh -- Sparks installer
# =============================================================================
#
# Usage:
#   ./install.sh            Deploy framework files to install location
#   ./install.sh --status   Print health/drift report
#   ./install.sh --help     Show this help
#
# Overridable env vars (for testing):
#   SPARKS_INSTALL_DIR      Default: ~/.local/share/sparks
#   SPARKS_CONFIG_DIR       Default: ~/.config/sparks
#   SPARKS_PLUGINS_CONF     Default: ~/.config/shellfire/plugins.conf
#   SPARKS_GEMINI_SETTINGS  Default: ~/.gemini/settings.json
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
INSTALL_DIR="${SPARKS_INSTALL_DIR:-${HOME}/.local/share/sparks}"
CONFIG_DIR="${SPARKS_CONFIG_DIR:-${HOME}/.config/sparks}"
PLUGINS_CONF="${SPARKS_PLUGINS_CONF:-${HOME}/.config/shellfire/plugins.conf}"
GEMINI_SETTINGS="${SPARKS_GEMINI_SETTINGS:-${HOME}/.gemini/settings.json}"

_usage() {
  cat <<EOF
Usage: $(basename "$0") [--status] [--help]

  (no args)   Deploy framework files from dev clone to install location
  --status    Print health/drift report with fix suggestions
  --help      Show this help

Overridable env vars (for testing):
  SPARKS_INSTALL_DIR      Default: ~/.local/share/sparks
  SPARKS_CONFIG_DIR       Default: ~/.config/sparks
  SPARKS_PLUGINS_CONF     Default: ~/.config/shellfire/plugins.conf
  SPARKS_GEMINI_SETTINGS  Default: ~/.gemini/settings.json
EOF
}

_get_dev_commit() {
  local commit
  if commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)"; then
    echo "$commit"
  else
    echo "unknown"
  fi
}

_cmd_deploy() { echo "[deploy] not yet implemented"; }
_cmd_status() { echo "[status] not yet implemented"; }

# Allow sourcing for testing without executing commands
[[ "${1:-}" == "--_source-only" ]] && return 0 2>/dev/null || true

case "${1:-}" in
  --help|-h)       _usage; exit 0 ;;
  --status)        _cmd_status; exit $? ;;
  --_source-only)  exit 0 ;;
  "")              _cmd_deploy; exit $? ;;
  *)               echo "Unknown option: $1" >&2; _usage >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash tests/test_installer.bash -s help
bash tests/test_installer.bash -s commit
```

Expected: all ok (commit should be a 40-char hex)

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_installer.bash
git commit -m "feat: add install.sh skeleton with --help and _get_dev_commit"
```

---

### Task 3: Implement deploy mode

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_installer.bash`

- [ ] **Step 1: Add deploy tests before `_summary`**

```bash
_should_run "deploy" && {
  _section "deploy - fresh install"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "deploy exits 0" "$exit_code" "0"
  _assert_contains "deploy reports source" "$output" "[deploy]"
  _assert_contains "deploy reports done" "$output" "done"
  [[ -f "${SPARKS_INSTALL_DIR}/sparks.bash" ]] \
    && _ok "sparks.bash deployed" \
    || _fail "sparks.bash not found in install dir"
  [[ -d "${SPARKS_INSTALL_DIR}/lib" ]] \
    && _ok "lib/ deployed" \
    || _fail "lib/ not found in install dir"
  [[ -d "${SPARKS_INSTALL_DIR}/adapters" ]] \
    && _ok "adapters/ deployed" \
    || _fail "adapters/ not found in install dir"
  [[ -f "${SPARKS_INSTALL_DIR}/VERSION" ]] \
    && _ok "VERSION stamp written" \
    || _fail "VERSION stamp not found"
  _assert_contains "VERSION has commit=" "$(cat "${SPARKS_INSTALL_DIR}/VERSION")" "commit="
  _assert_contains "VERSION has deployed_at=" "$(cat "${SPARKS_INSTALL_DIR}/VERSION")" "deployed_at="
  _cleanup_tmpenv

  _section "deploy - excluded files not in install dir"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  [[ ! -f "${SPARKS_INSTALL_DIR}/install.sh" ]] \
    && _ok "install.sh not in install dir" \
    || _fail "install.sh should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/.git" ]] \
    && _ok ".git not in install dir" \
    || _fail ".git should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/tests" ]] \
    && _ok "tests/ not in install dir" \
    || _fail "tests/ should not be in install dir"
  [[ ! -d "${SPARKS_INSTALL_DIR}/docs" ]] \
    && _ok "docs/ not in install dir" \
    || _fail "docs/ should not be in install dir"
  _cleanup_tmpenv

  _section "deploy - idempotent"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  output="$(bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "second deploy exits 0" "$exit_code" "0"
  _assert_contains "second deploy reports done" "$output" "done"
  _cleanup_tmpenv

  _section "deploy - deploy-to-self refused"
  _make_tmpenv
  output="$(SPARKS_INSTALL_DIR="$REPO_DIR" bash "$INSTALLER" 2>&1)"
  exit_code=$?
  _assert_exit "deploy-to-self exits non-zero" "$exit_code" "1"
  _assert_contains "deploy-to-self error message" "$output" "Cannot deploy"
  _cleanup_tmpenv

  _section "deploy - suggests config scaffold when missing"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests config scaffold" "$output" "[suggest]"
  _assert_contains "suggests mkdir for personas" "$output" "mkdir -p"
  _assert_contains "mentions sparks.conf" "$output" "sparks.conf"
  _cleanup_tmpenv

  _section "deploy - suggests @sparks in plugins.conf"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests @sparks" "$output" "@sparks"
  _assert_contains "mentions plugins.conf" "$output" "plugins.conf"
  _cleanup_tmpenv

  _section "deploy - suggests gemini settings"
  _make_tmpenv
  output="$(bash "$INSTALLER" 2>&1)"
  _assert_contains "suggests gemini context block" "$output" "context.fileName"
  _cleanup_tmpenv

  _section "deploy - no config suggestion when config exists"
  _make_tmpenv
  mkdir -p "${SPARKS_CONFIG_DIR}/personas"
  touch "${SPARKS_CONFIG_DIR}/sparks.conf"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"mkdir -p ${SPARKS_CONFIG_DIR}"* ]]; then
    _ok "no config scaffold suggestion when config already exists"
  else
    _fail "config scaffold suggested even though config dir exists"
  fi
  _cleanup_tmpenv

  _section "deploy - no plugins.conf suggestion when @sparks present"
  _make_tmpenv
  echo "@sparks" > "${SPARKS_PLUGINS_CONF}"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"@sparks not found"* ]]; then
    _ok "no @sparks suggestion when already present"
  else
    _fail "@sparks suggestion shown even though already in plugins.conf"
  fi
  _cleanup_tmpenv

  _section "deploy - no gemini suggestion when context.fileName present"
  _make_tmpenv
  printf '{"context":{"fileName":["AGENTS.md"]}}\n' > "${SPARKS_GEMINI_SETTINGS}"
  output="$(bash "$INSTALLER" 2>&1)"
  if [[ "$output" != *"context.fileName not found"* ]]; then
    _ok "no gemini suggestion when context.fileName present"
  else
    _fail "gemini suggestion shown even though context.fileName is configured"
  fi
  _cleanup_tmpenv
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
bash tests/test_installer.bash -s deploy
```

Expected: multiple FAILs

- [ ] **Step 3: Implement deploy in `install.sh`**

Replace `_cmd_deploy() { echo "[deploy] not yet implemented"; }` with the full implementation plus three suggest helpers. Place all four functions before the `--_source-only` guard.

```bash
_cmd_deploy() {
  local commit deployed_at

  # Safety: refuse to deploy to self
  if [[ "$(realpath "$SCRIPT_DIR")" == "$(realpath "$INSTALL_DIR" 2>/dev/null || echo "__none__")" ]]; then
    echo "Cannot deploy: source and install dir are the same path: $SCRIPT_DIR" >&2
    return 1
  fi

  commit="$(_get_dev_commit)"
  if [[ "$commit" == "unknown" ]]; then
    echo "[warn]   could not read git commit from dev clone — VERSION will show 'unknown'"
  fi

  echo "[deploy] source: $SCRIPT_DIR (commit: $commit)"
  echo "[deploy] target: $INSTALL_DIR"
  echo "[deploy] syncing framework files..."

  mkdir -p "$INSTALL_DIR"

  rsync -a --delete \
    --exclude='.git/' \
    --exclude='.gitignore' \
    --exclude='tests/' \
    --exclude='docs/' \
    --exclude='install.sh' \
    --exclude='AGENTS.md' \
    --exclude='README.md' \
    --exclude='INSTALL.md' \
    "${SCRIPT_DIR}/" "${INSTALL_DIR}/"

  deployed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf 'commit=%s\ndeployed_at=%s\n' "$commit" "$deployed_at" \
    > "${INSTALL_DIR}/VERSION"

  echo "[deploy] done. VERSION stamp written."
  echo

  _suggest_config
  _suggest_plugins_conf
  _suggest_gemini
}

_suggest_config() {
  if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "[suggest] ${CONFIG_DIR} not found. To scaffold your config directory:"
    echo "    mkdir -p ${CONFIG_DIR}/personas"
    echo "    touch ${CONFIG_DIR}/sparks.conf"
    echo
  fi
}

_suggest_plugins_conf() {
  if [[ ! -f "$PLUGINS_CONF" ]] || ! grep -q "^@sparks" "$PLUGINS_CONF" 2>/dev/null; then
    echo "[suggest] @sparks not found in ${PLUGINS_CONF}. Add:"
    echo "    echo '@sparks' >> ${PLUGINS_CONF}"
    echo
  fi
}

_suggest_gemini() {
  if [[ ! -f "$GEMINI_SETTINGS" ]] || ! grep -q "context.fileName" "$GEMINI_SETTINGS" 2>/dev/null; then
    echo "[suggest] context.fileName not found in ${GEMINI_SETTINGS}. Add:"
    echo '    {'
    echo '      "context": {'
    echo '        "fileName": ["AGENTS.md", "GEMINI.md"]'
    echo '      }'
    echo '    }'
    echo
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bash tests/test_installer.bash -s deploy
```

Expected: all ok

- [ ] **Step 5: Run full suite to verify no regressions**

```bash
bash tests/test_installer.bash
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/test_installer.bash
git commit -m "feat: implement deploy mode in install.sh"
```

---

### Task 4: Implement status mode

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_installer.bash`

- [ ] **Step 1: Add status tests before `_summary`**

```bash
_should_run "status" && {
  _section "status - no install"
  _make_tmpenv
  output="$(bash "$INSTALLER" --status 2>&1)"
  exit_code=$?
  _assert_exit "status exits 1 with no install" "$exit_code" "1"
  _assert_contains "reports missing install dir" "$output" "[missing]"
  _assert_contains "suggests install command" "$output" "./install.sh"
  _cleanup_tmpenv

  _section "status - current install (no drift)"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports ok for install dir" "$output" "[ok]"
  if [[ "$output" != *"[drift]"* ]]; then
    _ok "no drift on fresh deploy"
  else
    _fail "drift reported on just-deployed install"
  fi
  _cleanup_tmpenv

  _section "status - drifted install"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  sed -i.bak 's/^commit=.*/commit=0000000000000000000000000000000000000000/' \
    "${SPARKS_INSTALL_DIR}/VERSION"
  rm -f "${SPARKS_INSTALL_DIR}/VERSION.bak"
  output="$(bash "$INSTALLER" --status 2>&1)"
  exit_code=$?
  _assert_exit "status exits 1 on drift" "$exit_code" "1"
  _assert_contains "reports drift" "$output" "[drift]"
  _assert_contains "drift suggests deploy" "$output" "./install.sh"
  _cleanup_tmpenv

  _section "status - missing VERSION stamp"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  rm "${SPARKS_INSTALL_DIR}/VERSION"
  output="$(bash "$INSTALLER" --status 2>&1)"
  exit_code=$?
  _assert_exit "status exits 1 on missing VERSION" "$exit_code" "1"
  _assert_contains "reports warn for missing VERSION" "$output" "[warn]"
  _cleanup_tmpenv

  _section "status - missing config dir"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing config dir" "$output" "[missing]"
  _assert_contains "suggests mkdir" "$output" "mkdir -p"
  _cleanup_tmpenv

  _section "status - missing personas dir"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  mkdir -p "${SPARKS_CONFIG_DIR}"
  touch "${SPARKS_CONFIG_DIR}/sparks.conf"
  # personas dir not created
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing personas dir" "$output" "[missing]"
  _assert_contains "suggests personas mkdir" "$output" "personas"
  _cleanup_tmpenv

  _section "status - missing sparks.conf"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  mkdir -p "${SPARKS_CONFIG_DIR}/personas"
  # sparks.conf not created
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing sparks.conf" "$output" "[missing]"
  _assert_contains "suggests touch sparks.conf" "$output" "sparks.conf"
  _cleanup_tmpenv

  _section "status - @sparks missing from plugins.conf"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  # SPARKS_PLUGINS_CONF points to a non-existent file
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing @sparks" "$output" "[missing]"
  _assert_contains "suggests @sparks" "$output" "@sparks"
  _cleanup_tmpenv

  _section "status - @sparks present in plugins.conf"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  echo "@sparks" > "${SPARKS_PLUGINS_CONF}"
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports ok for @sparks" "$output" "[ok]"
  if [[ "$output" != *"@sparks not found"* ]]; then
    _ok "@sparks not flagged as missing"
  else
    _fail "@sparks incorrectly flagged as missing"
  fi
  _cleanup_tmpenv

  _section "status - gemini settings missing"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  # SPARKS_GEMINI_SETTINGS points to non-existent file
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing gemini config" "$output" "[missing]"
  _assert_contains "suggests context.fileName" "$output" "context.fileName"
  _cleanup_tmpenv

  _section "status - gemini settings missing context.fileName"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  printf '{"theme":"dark"}\n' > "${SPARKS_GEMINI_SETTINGS}"
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports missing context.fileName" "$output" "[missing]"
  _cleanup_tmpenv

  _section "status - gemini fully configured"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  printf '{"context":{"fileName":["AGENTS.md","GEMINI.md"]}}\n' > "${SPARKS_GEMINI_SETTINGS}"
  output="$(bash "$INSTALLER" --status 2>&1)"
  _assert_contains "reports ok for gemini" "$output" "[ok]"
  if [[ "$output" != *"context.fileName not found"* ]]; then
    _ok "gemini not flagged when configured"
  else
    _fail "gemini incorrectly flagged as missing"
  fi
  _cleanup_tmpenv

  _section "status - all ok"
  _make_tmpenv
  bash "$INSTALLER" >/dev/null 2>&1
  mkdir -p "${SPARKS_CONFIG_DIR}/personas"
  touch "${SPARKS_CONFIG_DIR}/sparks.conf"
  echo "@sparks" > "${SPARKS_PLUGINS_CONF}"
  printf '{"context":{"fileName":["AGENTS.md","GEMINI.md"]}}\n' > "${SPARKS_GEMINI_SETTINGS}"
  output="$(bash "$INSTALLER" --status 2>&1)"
  exit_code=$?
  _assert_exit "status exits 0 when all ok" "$exit_code" "0"
  if [[ "$output" != *"[missing]"* && "$output" != *"[drift]"* && "$output" != *"[warn]"* ]]; then
    _ok "no issues reported when fully configured"
  else
    _fail "unexpected issues reported: $output"
  fi
  _cleanup_tmpenv
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
bash tests/test_installer.bash -s status
```

Expected: multiple FAILs

- [ ] **Step 3: Implement `_cmd_status` and helpers in `install.sh`**

Replace `_cmd_status() { echo "[status] not yet implemented"; }` with the full implementation. Use global `_status_issues` counter (no namerefs — bash 3.2 compat).

```bash
# Global issue counter used by _status_* helpers.
# Avoids bash 4.3+ namerefs (macOS ships bash 3.2).
_status_issues=0

_cmd_status() {
  _status_issues=0

  # Check 1: install dir
  if [[ -d "$INSTALL_DIR" ]]; then
    echo "[ok]     install dir exists: $INSTALL_DIR"
  else
    echo "[missing] install dir not found: $INSTALL_DIR"
    echo "         run: ./install.sh"
    _status_issues=$(( _status_issues + 1 ))
    _status_config
    _status_plugins_conf
    _status_gemini
    [[ "$_status_issues" -eq 0 ]] && return 0 || return 1
  fi

  # Check 2: VERSION stamp + drift
  local version_file="${INSTALL_DIR}/VERSION"
  if [[ ! -f "$version_file" ]]; then
    echo "[warn]   no VERSION stamp in install dir"
    echo "         run: ./install.sh"
    _status_issues=$(( _status_issues + 1 ))
  else
    local installed_commit dev_commit
    installed_commit="$(grep '^commit=' "$version_file" | cut -d= -f2)"
    dev_commit="$(_get_dev_commit)"

    echo "[ok]     VERSION stamp present (installed commit: ${installed_commit:-unknown})"

    if [[ "$dev_commit" == "unknown" ]]; then
      echo "[warn]   could not read dev clone git commit — cannot check drift"
      _status_issues=$(( _status_issues + 1 ))
    elif [[ "$installed_commit" == "$dev_commit" ]]; then
      echo "[ok]     install is current (${dev_commit:0:8})"
    else
      echo "[drift]  install=${installed_commit:0:8}, dev=${dev_commit:0:8}"
      echo "         run: ./install.sh"
      _status_issues=$(( _status_issues + 1 ))
    fi
  fi

  _status_config
  _status_plugins_conf
  _status_gemini

  [[ "$_status_issues" -eq 0 ]] && return 0 || return 1
}

_status_config() {
  if [[ ! -d "$CONFIG_DIR" ]]; then
    echo "[missing] config dir not found: $CONFIG_DIR"
    echo "         run: mkdir -p ${CONFIG_DIR}/personas && touch ${CONFIG_DIR}/sparks.conf"
    _status_issues=$(( _status_issues + 1 ))
    return
  fi
  echo "[ok]     config dir exists: $CONFIG_DIR"

  if [[ ! -d "${CONFIG_DIR}/personas" ]]; then
    echo "[missing] personas dir not found: ${CONFIG_DIR}/personas"
    echo "         run: mkdir -p ${CONFIG_DIR}/personas"
    _status_issues=$(( _status_issues + 1 ))
  else
    echo "[ok]     personas dir exists"
  fi

  if [[ ! -f "${CONFIG_DIR}/sparks.conf" ]]; then
    echo "[missing] sparks.conf not found: ${CONFIG_DIR}/sparks.conf"
    echo "         run: touch ${CONFIG_DIR}/sparks.conf"
    _status_issues=$(( _status_issues + 1 ))
  else
    echo "[ok]     sparks.conf exists"
  fi
}

_status_plugins_conf() {
  if [[ -f "$PLUGINS_CONF" ]] && grep -q "^@sparks" "$PLUGINS_CONF" 2>/dev/null; then
    echo "[ok]     @sparks in ${PLUGINS_CONF}"
  else
    echo "[missing] @sparks not found in ${PLUGINS_CONF}"
    echo "         run: echo '@sparks' >> ${PLUGINS_CONF}"
    _status_issues=$(( _status_issues + 1 ))
  fi
}

_status_gemini() {
  if [[ -f "$GEMINI_SETTINGS" ]] && grep -q "context.fileName" "$GEMINI_SETTINGS" 2>/dev/null; then
    echo "[ok]     gemini context.fileName configured in ${GEMINI_SETTINGS}"
  else
    echo "[missing] context.fileName not found in ${GEMINI_SETTINGS}"
    echo "         add to ${GEMINI_SETTINGS}:"
    echo '           {'
    echo '             "context": {'
    echo '               "fileName": ["AGENTS.md", "GEMINI.md"]'
    echo '             }'
    echo '           }'
    _status_issues=$(( _status_issues + 1 ))
  fi
}
```

- [ ] **Step 4: Run status tests**

```bash
bash tests/test_installer.bash -s status
```

Expected: all ok

- [ ] **Step 5: Run full test suite**

```bash
bash tests/test_installer.bash
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/test_installer.bash
git commit -m "feat: implement status mode in install.sh"
```

---

### Task 5: Final verification and chmod

**Files:**
- Modify: `install.sh` (make executable)

- [ ] **Step 1: Run full installer test suite**

```bash
bash tests/test_installer.bash
```

Expected: all pass, `0 failed`

- [ ] **Step 2: Run existing sparks test suite to confirm nothing broken**

```bash
bash tests/test_sparks.bash
```

Expected: all pass

- [ ] **Step 3: Make install.sh executable**

```bash
chmod +x install.sh
```

- [ ] **Step 4: Smoke test against real environment**

```bash
./install.sh --help
./install.sh --status
```

Review output manually. Do NOT run `./install.sh` without flags (that would deploy to real location).

- [ ] **Step 5: Commit if chmod changed tracked state**

```bash
git add install.sh
git diff --cached --quiet || git commit -m "chore: make install.sh executable"
```
