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
  if [[ ! -f "$GEMINI_SETTINGS" ]] || ! grep -q '"fileName"' "$GEMINI_SETTINGS" 2>/dev/null; then
    echo "[suggest] context.fileName not found in ${GEMINI_SETTINGS}. Add:"
    echo '    {'
    echo '      "context": {'
    echo '        "fileName": ["AGENTS.md", "GEMINI.md"]'
    echo '      }'
    echo '    }'
    echo
  fi
}

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
  if [[ -f "$GEMINI_SETTINGS" ]] && grep -q '"fileName"' "$GEMINI_SETTINGS" 2>/dev/null; then
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

# Allow sourcing for testing without executing commands
[[ "${1:-}" == "--_source-only" ]] && return 0 2>/dev/null || true

case "${1:-}" in
  --help|-h)       _usage; exit 0 ;;
  --status)        _cmd_status; exit $? ;;
  --_source-only)  exit 0 ;;
  "")              _cmd_deploy; exit $? ;;
  *)               echo "Unknown option: $1" >&2; _usage >&2; exit 1 ;;
esac
