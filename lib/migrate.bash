#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/migrate.bash — Migrate from ai-cli to Sparks
# =============================================================================
#
# Converts ai-cli persona configuration to the Sparks format:
#   - .ai-personas files → .sparks files
#   - Old-format AGENTS.md/CLAUDE.md/etc → sentinel-wrapped versions
#   - ~/.config/ai/personas/ → ~/.config/sparks/personas/ (if not done)
#
# Usage (standalone):
#   bash ~/.config/bash/plugins/sparks/migrate.bash [--dry-run]
#
# Usage (from sparks command):
#   sparks migrate [--dry-run]
#
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_MIGRATE_DRY_RUN=false
_MIGRATE_VERBOSE=true

# Colors
_M_RESET=$'\033[0m'
_M_BOLD=$'\033[1m'
_M_DIM=$'\033[2m'
_M_GREEN=$'\033[32m'
_M_YELLOW=$'\033[33m'
_M_RED=$'\033[31m'
_M_CYAN=$'\033[36m'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) _MIGRATE_DRY_RUN=true; shift ;;
    --quiet|-q) _MIGRATE_VERBOSE=false; shift ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_m_info()  { printf '  %b▸%b %s\n' "${_M_CYAN}" "${_M_RESET}" "$*"; }
_m_ok()    { printf '  %b✔%b %s\n' "${_M_GREEN}" "${_M_RESET}" "$*"; }
_m_warn()  { printf '  %b⚠%b %s\n' "${_M_YELLOW}" "${_M_RESET}" "$*"; }
_m_error() { printf '  %b✘%b %s\n' "${_M_RED}" "${_M_RESET}" "$*" >&2; }
_m_dry()   { printf '  %b[dry-run]%b %s\n' "${_M_DIM}" "${_M_RESET}" "$*"; }

_m_action() {
  if [[ "${_MIGRATE_DRY_RUN}" == true ]]; then
    _m_dry "$*"
    return 1  # signal: action was skipped
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SPARKS_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/sparks"
SPARKS_PERSONAS_DIR="${SPARKS_CONFIG_DIR}/personas"
AI_CLI_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/ai"
AI_CLI_PERSONAS_DIR="${AI_CLI_CONFIG_DIR}/personas"
AI_CLI_BASE_CANDIDATES=(
  "${HOME}/digital/ai/personal/ai_framework/ai-cli/personas/base.md"
  "${AI_CLI_CONFIG_DIR}/personas/base.md"
)

# Adapter file names (ai-cli generates these same files)
_ADAPTER_FILES=("AGENTS.md" "CLAUDE.md" "GEMINI.md" ".github/copilot-instructions.md")

# ---------------------------------------------------------------------------
# Step 1: Migrate personas from ~/.config/ai/personas → ~/.config/sparks/personas
# ---------------------------------------------------------------------------

_migrate_personas() {
  printf '\n%b═══ Step 1: Migrate persona files ═══%b\n\n' "${_M_BOLD}" "${_M_RESET}"

  if [[ ! -d "${AI_CLI_PERSONAS_DIR}" ]]; then
    _m_info "No ai-cli personas found at ${AI_CLI_PERSONAS_DIR} — skipping"
    return 0
  fi

  # Ensure target exists
  if _m_action "Create ${SPARKS_PERSONAS_DIR}"; then
    mkdir -p "${SPARKS_PERSONAS_DIR}"
  fi

  # Migrate base.md (from ai-cli repo, not the central store)
  if [[ ! -f "${SPARKS_PERSONAS_DIR}/base.md" ]]; then
    local base_src=""
    for candidate in "${AI_CLI_BASE_CANDIDATES[@]}"; do
      if [[ -f "${candidate}" ]]; then
        base_src="${candidate}"
        break
      fi
    done

    if [[ -n "${base_src}" ]]; then
      if _m_action "Copy base.md from ${base_src}"; then
        cp "${base_src}" "${SPARKS_PERSONAS_DIR}/base.md"
        _m_ok "Migrated: base.md"
      fi
    else
      _m_warn "No base.md found in ai-cli — create one manually"
    fi
  else
    _m_info "base.md already exists in sparks — skipping"
  fi

  # Migrate each persona from the central store
  local persona_file
  for persona_file in "${AI_CLI_PERSONAS_DIR}"/*.md; do
    [[ -f "${persona_file}" ]] || continue
    local name="${persona_file##*/}"

    if [[ -f "${SPARKS_PERSONAS_DIR}/${name}" ]]; then
      _m_info "${name} already exists in sparks — skipping"
      continue
    fi

    if _m_action "Copy ${name} → ${SPARKS_PERSONAS_DIR}/${name}"; then
      cp "${persona_file}" "${SPARKS_PERSONAS_DIR}/${name}"
      _m_ok "Migrated: ${name}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Step 2: Find and convert .ai-personas → .sparks
# ---------------------------------------------------------------------------

_migrate_sparks_files() {
  printf '\n%b═══ Step 2: Convert .ai-personas → .sparks ═══%b\n\n' "${_M_BOLD}" "${_M_RESET}"

  # Find all .ai-personas files under HOME (limited depth, skip heavy dirs)
  local -a found_files=()
  while IFS= read -r -d '' file; do
    found_files+=("${file}")
  done < <(find "${HOME}" -maxdepth 6 \
    -name ".ai-personas" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/Library/*' \
    -not -path '*/.cache/*' \
    -not -path '*/.local/*' \
    -not -path '*/.npm/*' \
    -not -path '*/.cargo/*' \
    -not -path '*/.rustup/*' \
    -print0 2>/dev/null)

  if (( ${#found_files[@]} == 0 )); then
    _m_info "No .ai-personas files found"
    return 0
  fi

  _m_info "Found ${#found_files[@]} .ai-personas file(s)"

  local file
  for file in "${found_files[@]}"; do
    local dir
    dir="$(dirname "${file}")"
    local sparks_file="${dir}/.sparks"

    _m_info "  ${file}"

    # Check if .sparks already exists
    if [[ -f "${sparks_file}" ]]; then
      _m_warn "  .sparks already exists in ${dir} — skipping"
      continue
    fi

    # Parse the .ai-personas file: extract persona names (skip comments, blanks)
    local -a persona_names=()
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "${line}" || "${line}" == \#* ]] && continue
      # ai-cli format: "name  @hash" — extract just the name
      local name="${line%%[[:space:]]*}"
      [[ -n "${name}" ]] && persona_names+=("${name}")
    done < "${file}"

    if (( ${#persona_names[@]} == 0 )); then
      _m_warn "  No personas found in ${file} — skipping"
      continue
    fi

    _m_info "  Personas: ${persona_names[*]}"

    if _m_action "Create ${sparks_file} with: ${persona_names[*]}"; then
      {
        echo "# Sparks active personas"
        echo "# Migrated from .ai-personas on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "#"
        printf '%s\n' "${persona_names[@]}"
      } > "${sparks_file}"
      _m_ok "Created: ${sparks_file}"
    fi
  done
}

# ---------------------------------------------------------------------------
# Step 3: Replace old-format generated files with sentinel versions
# ---------------------------------------------------------------------------

_migrate_generated_files() {
  printf '\n%b═══ Step 3: Replace generated files with sentinel format ═══%b\n\n' "${_M_BOLD}" "${_M_RESET}"

  # Find directories that have a new .sparks file (from step 2)
  local -a sparks_dirs=()
  while IFS= read -r -d '' file; do
    sparks_dirs+=("$(dirname "${file}")")
  done < <(find "${HOME}" -maxdepth 6 \
    -name ".sparks" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/Library/*' \
    -not -path '*/.cache/*' \
    -print0 2>/dev/null)

  if (( ${#sparks_dirs[@]} == 0 )); then
    _m_info "No .sparks directories found — skipping"
    return 0
  fi

  local dir
  for dir in "${sparks_dirs[@]}"; do
    _m_info "Checking: ${dir}"

    local needs_apply=false
    local adapter_file
    for adapter_file in "${_ADAPTER_FILES[@]}"; do
      local target="${dir}/${adapter_file}"
      [[ -f "${target}" ]] || continue

      # Check if already has sentinel markers
      if grep -q '^<!-- sparks:begin' "${target}" 2>/dev/null; then
        _m_info "  ${adapter_file}: already has sparks sentinels"
        continue
      fi

      # Check if this file was generated by ai-cli (contains the ai-cli marker)
      if grep -q 'Generated by ai-cli' "${target}" 2>/dev/null || \
         grep -q 'ai personas apply' "${target}" 2>/dev/null; then
        _m_info "  ${adapter_file}: ai-cli generated file detected"
        needs_apply=true
      else
        # File exists but doesn't look ai-cli generated — might have user content
        _m_warn "  ${adapter_file}: exists but not ai-cli generated — will append sentinel on next 'sparks apply'"
      fi
    done

    if [[ "${needs_apply}" == true ]]; then
      _m_info "  → Run 'sparks apply' in ${dir} to regenerate with sentinels"
    fi
  done
}

# ---------------------------------------------------------------------------
# Step 4: Clean up old .ai-personas files (optional, with backup)
# ---------------------------------------------------------------------------

_migrate_cleanup() {
  printf '\n%b═══ Step 4: Clean up old files ═══%b\n\n' "${_M_BOLD}" "${_M_RESET}"

  local -a ai_personas_files=()
  while IFS= read -r -d '' file; do
    ai_personas_files+=("${file}")
  done < <(find "${HOME}" -maxdepth 6 \
    -name ".ai-personas" -type f \
    -not -path '*/.git/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/Library/*' \
    -not -path '*/.cache/*' \
    -print0 2>/dev/null)

  if (( ${#ai_personas_files[@]} == 0 )); then
    _m_info "No .ai-personas files to clean up"
    return 0
  fi

  local file
  for file in "${ai_personas_files[@]}"; do
    local dir
    dir="$(dirname "${file}")"
    local sparks_file="${dir}/.sparks"

    # Only clean up if .sparks was successfully created
    if [[ -f "${sparks_file}" ]]; then
      if _m_action "Rename ${file} → ${file}.bak"; then
        mv "${file}" "${file}.bak"
        _m_ok "Backed up: ${file} → ${file}.bak"
      fi
    else
      _m_warn "Skipping ${file} — no .sparks replacement yet"
    fi
  done

  # Note about ai shell function
  _m_info ""
  _m_info "To complete the migration:"
  _m_info "  1. Run 'sparks apply' in each project directory"
  _m_info "  2. Remove 'source .../ai-cli/ai.sh' from your shell profile"
  _m_info "  3. Add 'sparks' to ~/.config/bash/plugins.conf"
  _m_info "  4. Delete .ai-personas.bak files once you're satisfied"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf '\n'
printf '  %b✦ Sparks Migration Tool%b\n' "${_M_BOLD}" "${_M_RESET}"
printf '  %b─────────────────────────────────────────%b\n' "${_M_DIM}" "${_M_RESET}"
if [[ "${_MIGRATE_DRY_RUN}" == true ]]; then
  printf '  %bMode: dry-run (no changes will be made)%b\n' "${_M_YELLOW}" "${_M_RESET}"
fi
printf '\n'

_migrate_personas
_migrate_sparks_files
_migrate_generated_files
_migrate_cleanup

printf '\n'
printf '  %b─────────────────────────────────────────%b\n' "${_M_DIM}" "${_M_RESET}"
printf '  %b✔ Migration complete%b\n\n' "${_M_GREEN}" "${_M_RESET}"
