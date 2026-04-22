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
