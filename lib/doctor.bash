#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/doctor.bash — Sparks system health checker
# =============================================================================
#
# What this module does:
#   Checks the full sparks configuration and reports issues. Covers:
#     1. Core configuration (dirs, sparks.conf, adapters, required tools)
#     2. Persona store integrity (frontmatter, name/file match, body)
#     3. .sparks file hierarchy (unknown personas, duplicates)
#     4. Output file state (staleness, version drift, bootstrap setup)
#
#   In "fix" mode, applies all safe auto-fixes and re-runs the check.
#
# Entry point:
#   _sparks_doctor [fix]
#
# =============================================================================

# ---------------------------------------------------------------------------
# Colour helpers (ui.bash may not be loaded when doctor runs standalone)
# ---------------------------------------------------------------------------
_SPARKS_DR_RESET=$'\033[0m'
_SPARKS_DR_BOLD=$'\033[1m'
_SPARKS_DR_GREEN=$'\033[38;5;114m'
_SPARKS_DR_YELLOW=$'\033[38;5;221m'
_SPARKS_DR_RED=$'\033[38;5;204m'
_SPARKS_DR_GREY=$'\033[38;5;243m'
_SPARKS_DR_CYAN=$'\033[38;5;75m'
_SPARKS_DR_SPARK=$'\033[38;5;208m'

# Track overall result across this run (reset at top of _sparks_doctor)
_sparks_dr_errors=0
_sparks_dr_warnings=0
_sparks_dr_unset=0

_sparks_dr_ok() {
  printf '    %b✔%b  %-20s %b%s%b\n' \
    "${_SPARKS_DR_GREEN}" "${_SPARKS_DR_RESET}" \
    "$1" "${_SPARKS_DR_GREY}" "${2:-}" "${_SPARKS_DR_RESET}"
}

_sparks_dr_warn() {
  (( _sparks_dr_warnings++ )) || true
  printf '    %b!%b  %-20s %b%s%b\n' \
    "${_SPARKS_DR_YELLOW}" "${_SPARKS_DR_RESET}" \
    "$1" "${_SPARKS_DR_YELLOW}" "${2:-}" "${_SPARKS_DR_RESET}"
}

_sparks_dr_err() {
  (( _sparks_dr_errors++ )) || true
  printf '    %b✗%b  %-20s %b%s%b\n' \
    "${_SPARKS_DR_RED}" "${_SPARKS_DR_RESET}" \
    "$1" "${_SPARKS_DR_RED}" "${2:-}" "${_SPARKS_DR_RESET}"
}

_sparks_dr_notset() {
  (( _sparks_dr_unset++ )) || true
  printf '    %b○%b  %-20s %b%s%b\n' \
    "${_SPARKS_DR_GREY}" "${_SPARKS_DR_RESET}" \
    "$1" "${_SPARKS_DR_GREY}" "${2:-}" "${_SPARKS_DR_RESET}"
}

_sparks_dr_fix_line() {
  printf '         %bFix:%b  %s\n' \
    "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}" "$1"
}

_sparks_dr_section() {
  printf '\n  %b%s%b\n' \
    "${_SPARKS_DR_GREY}" "$1 ──────────────────────────────────────────────" \
    "${_SPARKS_DR_RESET}"
}

# ---------------------------------------------------------------------------
# _sparks_doctor — main entry point
# ---------------------------------------------------------------------------
_sparks_doctor() {
  local mode="${1:-}"

  # Reset counters for this run
  _sparks_dr_errors=0
  _sparks_dr_warnings=0
  _sparks_dr_unset=0

  local dir="${PWD}"
  local target_dir
  target_dir=$(_sparks_find_target_dir "${dir}" 2>/dev/null) || target_dir="${dir}"

  # Track whether any fix requires sparks apply
  local need_apply=0

  printf '\n  %b\n  %bsparks doctor%b — system health check\n' \
    "${_SPARKS_LOGO_LINE:-}" \
    "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}"

  # =========================================================================
  # Section 1: Core configuration
  # =========================================================================
  _sparks_dr_section "Core configuration"

  # Config dir
  if [[ -d "${SPARKS_CONFIG_DIR}" ]]; then
    _sparks_dr_ok "config dir" "${SPARKS_CONFIG_DIR/#${HOME}/\~}"
  else
    _sparks_dr_err "config dir" "${SPARKS_CONFIG_DIR/#${HOME}/\~} — not found"
    _sparks_dr_fix_line "mkdir -p ${SPARKS_CONFIG_DIR}"
    [[ "${mode}" == "fix" ]] && mkdir -p "${SPARKS_CONFIG_DIR}"
  fi

  # Personas dir
  if [[ -d "${SPARKS_PERSONAS_DIR}" ]]; then
    local persona_count
    persona_count=$(find "${SPARKS_PERSONAS_DIR}" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    _sparks_dr_ok "personas dir" "${SPARKS_PERSONAS_DIR/#${HOME}/\~} (${persona_count} personas)"
  else
    _sparks_dr_err "personas dir" "${SPARKS_PERSONAS_DIR/#${HOME}/\~} — not found"
    _sparks_dr_fix_line "mkdir -p ${SPARKS_PERSONAS_DIR}"
    [[ "${mode}" == "fix" ]] && mkdir -p "${SPARKS_PERSONAS_DIR}"
  fi

  # sparks.conf
  local conf_file="${SPARKS_CONFIG_DIR}/sparks.conf"
  if [[ -f "${conf_file}" ]]; then
    if bash -n "${conf_file}" 2>/dev/null; then
      _sparks_dr_ok "sparks.conf" "loaded OK"
    else
      _sparks_dr_err "sparks.conf" "syntax error — run: bash -n ${conf_file}"
    fi
  else
    _sparks_dr_warn "sparks.conf" "not found (using defaults)"
  fi

  # Active adapters — show which are configured
  local active_names="${SPARKS_ACTIVE_ADAPTERS[*]}"
  _sparks_dr_ok "active adapters" "${active_names}"

  local known_adapters=(opencode claude copilot gemini)
  for adapter in "${SPARKS_ACTIVE_ADAPTERS[@]}"; do
    local is_known=0
    for k in "${known_adapters[@]}"; do
      [[ "${k}" == "${adapter}" ]] && is_known=1 && break
    done
    if (( ! is_known )); then
      _sparks_dr_err "adapter: ${adapter}" "unknown adapter name"
      continue
    fi
    local adapter_file="${_SPARKS_PLUGIN_DIR}/adapters/${adapter}.bash"
    if [[ -f "${adapter_file}" ]]; then
      _sparks_dr_ok "adapter: ${adapter}" "${adapter_file/#${HOME}/\~}"
    else
      _sparks_dr_err "adapter: ${adapter}" "file not found: ${adapter_file/#${HOME}/\~}"
    fi
  done

  # base persona — always implicitly required
  if _sparks_persona_exists "base" 2>/dev/null; then
    _sparks_dr_ok "base persona" "found"
  else
    _sparks_dr_err "base persona" "not found — always implicitly active"
    _sparks_dr_fix_line "sparks new base"
  fi

  # Required tool: git (for target dir resolution)
  if command -v git &>/dev/null; then
    _sparks_dr_ok "tool: git" "$(command -v git)"
  else
    _sparks_dr_err "tool: git" "not found — required for target dir resolution"
  fi

  # Hash tool (for staleness detection)
  local hash_tool=""
  for t in md5sum md5 cksum; do
    command -v "${t}" &>/dev/null && hash_tool="${t}" && break
  done
  if [[ -n "${hash_tool}" ]]; then
    _sparks_dr_ok "tool: hash" "${hash_tool}"
  else
    _sparks_dr_err "tool: hash" "no md5sum/md5/cksum — staleness detection broken"
  fi

  # Optional tools
  if command -v fzf &>/dev/null; then
    _sparks_dr_ok "tool: fzf" "$(command -v fzf)"
  else
    _sparks_dr_warn "tool: fzf" "not found — sparks menu uses basic fallback"
  fi

  if command -v chezmoi &>/dev/null; then
    _sparks_dr_ok "tool: chezmoi" "$(command -v chezmoi)"
  else
    _sparks_dr_warn "tool: chezmoi" "not found — sparks sync unavailable"
  fi

  # =========================================================================
  # Section 2: Persona store integrity
  # =========================================================================
  _sparks_dr_section "Persona store"

  if [[ -d "${SPARKS_PERSONAS_DIR}" ]]; then
    local found_any=0
    while IFS= read -r pfile; do
      [[ -f "${pfile}" ]] || continue
      found_any=1
      local pname
      pname=$(basename "${pfile}" .md)
      local version
      version=$(_sparks_read_persona_meta "${pname}" "version" 2>/dev/null) || version=""
      local desc
      desc=$(_sparks_read_persona_meta "${pname}" "description" 2>/dev/null) || desc=""
      local -a issues=()

      # name field matches filename
      local name_field
      name_field=$(_sparks_read_persona_meta "${pname}" "name" 2>/dev/null) || name_field=""
      [[ -z "${name_field}" ]] && issues+=("name field missing in frontmatter")
      [[ -n "${name_field}" && "${name_field}" != "${pname}" ]] \
        && issues+=("name field '${name_field}' does not match filename '${pname}'")

      # description field
      [[ -z "${desc}" ]] && issues+=("description field missing")

      # non-empty body
      local body
      body=$(_sparks_read_persona_body "${pname}" 2>/dev/null) || body=""
      [[ -z "$(echo "${body}" | tr -d '[:space:]')" ]] && issues+=("body is empty")

      local version_str=""
      [[ -n "${version}" ]] && version_str="v${version}  "

      if (( ${#issues[@]} == 0 )); then
        local body_lines
        body_lines=$(echo "${body}" | wc -l | tr -d ' ')
        _sparks_dr_ok "${pname}" "${version_str}${body_lines} lines"
      else
        for issue in "${issues[@]}"; do
          _sparks_dr_warn "${pname}" "${version_str}${issue}"
        done
      fi
    done < <(find "${SPARKS_PERSONAS_DIR}" -name '*.md' | sort)

    (( found_any == 0 )) && _sparks_dr_warn "personas" "no .md files found in store"
  fi

  # =========================================================================
  # Section 3: .sparks file hierarchy
  # =========================================================================
  _sparks_dr_section ".sparks files (${dir/#${HOME}/\~})"

  local -a chain_files=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && chain_files+=("${f}")
  done < <(_sparks_inheritance_chain "${dir}" 2>/dev/null)

  if (( ${#chain_files[@]} == 0 )); then
    _sparks_dr_ok "no .sparks files" "only base persona active"
  else
    for sparks_file in "${chain_files[@]}"; do
      local short="${sparks_file/#${HOME}/\~}"
      local file_ok=1

      local -a seen_personas=()
      local -A seen_set=()
      while IFS= read -r entry; do
        [[ -z "${entry}" ]] && continue
        # Strip leading - to get the persona name for lookup
        local pname="${entry#-}"
        # Check for duplicates
        if [[ -n "${seen_set[${pname}]+_}" ]]; then
          _sparks_dr_warn "${short}" "duplicate entry: ${pname}"
          file_ok=0
        fi
        seen_set["${pname}"]=1
        seen_personas+=("${pname}")
        # Check persona exists (skip base — always valid)
        if [[ "${pname}" != "base" ]]; then
          if ! _sparks_persona_exists "${pname}" 2>/dev/null; then
            if [[ "${entry}" == -* ]]; then
              _sparks_dr_warn "${short}" \
                "exclusion '-${pname}' — persona not in store (defensive exclusion?)"
            else
              _sparks_dr_err "${short}" \
                "unknown persona: '${pname}' (not in central store)"
              _sparks_dr_fix_line "sparks new ${pname}"
              printf '         %bOr:%b   remove %s from %s\n' \
                "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}" "${pname}" "${short}"
              file_ok=0
            fi
          fi
        fi
      done < <(_sparks_read_sparks_file "${sparks_file}" 2>/dev/null)

      if (( file_ok )); then
        _sparks_dr_ok "${short}" "${seen_personas[*]}"
      fi
    done
  fi

  # =========================================================================
  # Section 4: Output files
  # =========================================================================
  _sparks_dr_section "Output files (${target_dir/#${HOME}/\~})"

  for adapter in "${SPARKS_ACTIVE_ADAPTERS[@]}"; do
    _sparks_load_adapter "${adapter}" 2>/dev/null || continue

    local file_fn="_sparks_adapter_${adapter}_file"
    declare -f "${file_fn}" &>/dev/null || continue

    local filename
    filename=$("${file_fn}")
    local target_file="${target_dir}/${filename}"

    if _sparks_adapter_check_stale "${adapter}" "${target_dir}" "${dir}"; then
      need_apply=1
      if [[ ! -f "${target_file}" ]]; then
        _sparks_dr_notset "${filename}" "not yet created"
        _sparks_dr_fix_line "sparks apply"
      else
        local is_stale_fn="_sparks_adapter_${adapter}_is_stale"
        if declare -f "${is_stale_fn}" &>/dev/null; then
          # Bootstrap adapter (e.g., claude) — import missing
          _sparks_dr_warn "${filename}" "not set up (@AGENTS.md import missing)"
          _sparks_dr_fix_line "sparks apply"
        else
          # Content adapter — sentinel is stale
          _sparks_dr_warn "${filename}" "stale — run sparks apply"
          _sparks_dr_fix_line "sparks apply"
        fi
      fi
    else
      # File is current — show version info
      local version_info=""
      if [[ -f "${target_file}" ]]; then
        local is_stale_fn="_sparks_adapter_${adapter}_is_stale"
        if declare -f "${is_stale_fn}" &>/dev/null; then
          # Bootstrap adapter — just confirm the import is present
          version_info="@AGENTS.md present"
          _sparks_dr_ok "${filename}" "${version_info}"
        else
          # Content adapter — check for version drift between installed and current
          local -a drift_parts=()
          while IFS= read -r vline; do
            local installed_ver
            installed_ver=$(echo "${vline}" | sed 's/.*persona-version: \(.*\) -->/\1/')
            # Find persona name from the ## Persona: line just before this comment
            local persona_context
            persona_context=$(grep -B2 "persona-version: ${installed_ver} " "${target_file}" \
              2>/dev/null | grep '^## Persona:' | tail -1 | sed 's/## Persona: //')
            if [[ -n "${persona_context}" ]]; then
              local current_ver
              current_ver=$(_sparks_read_persona_meta "${persona_context}" "version" \
                2>/dev/null) || current_ver=""
              if [[ -n "${current_ver}" && "${installed_ver}" != "${current_ver}" ]]; then
                drift_parts+=("${persona_context}: v${installed_ver}→v${current_ver}")
              fi
            fi
          done < <(grep '<!-- persona-version:' "${target_file}" 2>/dev/null)

          if (( ${#drift_parts[@]} > 0 )); then
            _sparks_dr_warn "${filename}" "version drift: ${drift_parts[*]}"
            _sparks_dr_fix_line "sparks apply"
            need_apply=1
          else
            _sparks_dr_ok "${filename}" "current"
          fi
        fi
      fi
    fi
  done

  # =========================================================================
  # Summary
  # =========================================================================
  printf '\n  %b──────────────────────────────────────────────────%b\n' \
    "${_SPARKS_DR_GREY}" "${_SPARKS_DR_RESET}"

  if (( _sparks_dr_errors == 0 && _sparks_dr_warnings == 0 && _sparks_dr_unset == 0 )); then
    printf '  %b✔ Everything looks good%b\n' "${_SPARKS_DR_GREEN}" "${_SPARKS_DR_RESET}"
  else
    [[ _sparks_dr_errors -gt 0 ]] && \
      printf '  %b%d error(s)%b' \
        "${_SPARKS_DR_RED}" "${_sparks_dr_errors}" "${_SPARKS_DR_RESET}"
    [[ _sparks_dr_warnings -gt 0 ]] && \
      printf '  %b%d warning(s)%b' \
        "${_SPARKS_DR_YELLOW}" "${_sparks_dr_warnings}" "${_SPARKS_DR_RESET}"
    [[ _sparks_dr_unset -gt 0 ]] && \
      printf '  %b%d not set up%b' \
        "${_SPARKS_DR_GREY}" "${_sparks_dr_unset}" "${_SPARKS_DR_RESET}"
    printf '\n'
    if [[ "${mode}" != "fix" ]] && (( need_apply || _sparks_dr_unset > 0 )); then
      printf '  Run: %bsparks doctor fix%b   to apply all safe fixes automatically\n' \
        "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}"
    fi
  fi
  printf '\n'

  # =========================================================================
  # Fix mode: run sparks apply then re-check
  # =========================================================================
  if [[ "${mode}" == "fix" ]] && (( need_apply || _sparks_dr_unset > 0 )); then
    printf '  %bApplying safe fixes...%b\n\n' "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}"
    _sparks_run_adapters "apply" "${target_dir}"
    printf '\n  %bRe-running doctor after fixes:%b\n' \
      "${_SPARKS_DR_BOLD}" "${_SPARKS_DR_RESET}"
    _sparks_dr_errors=0
    _sparks_dr_warnings=0
    _sparks_dr_unset=0
    _sparks_doctor ""
    return $?
  fi

  return $(( _sparks_dr_errors > 0 ? 1 : 0 ))
}
