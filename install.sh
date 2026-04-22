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
