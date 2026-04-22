#!/usr/bin/env bash
# =============================================================================
# plugins/sparks/ui.bash — Interactive UI, status banner, and fzf menus
# =============================================================================
#
# What this module does:
#   Provides the interactive user-facing components of Sparks:
#   - Compact status banner shown on cd (when personas change)
#   - fzf-based interactive persona selector (with basic fallback)
#   - Status display for the `sparks` and `sparks status` commands
#
# Dependencies:
#   _sparks_resolve_personas   (from plugins/sparks/core.bash)
#   _sparks_list_available     (from plugins/sparks/core.bash)
#   _sparks_persona_exists     (from plugins/sparks/core.bash)
#   _sparks_read_persona_meta  (from plugins/sparks/core.bash)
#   _sparks_inheritance_chain  (from plugins/sparks/core.bash)
#   _sparks_is_stale           (from plugins/sparks/render.bash)
#   __colours                  (from lib/colours.bash)
#   _log_info, _log_ok, etc.   (from lib/logging.bash)
#
# Exports (functions):
#   _sparks_banner             Print the compact cd status banner
#   _sparks_status             Print detailed status for `sparks` / `sparks status`
#   _sparks_menu               Interactive fzf persona selector
#   _sparks_show_help          Print help text
#
# =============================================================================

# Colours — using $'\033[...' for bash 3.2 compat (matches Shellfire convention)
_SPARKS_C_RESET=$'\033[0m'
_SPARKS_C_BOLD=$'\033[1m'
_SPARKS_C_DIM=$'\033[2m'
_SPARKS_C_SPARK=$'\033[38;5;208m'   # Orange — flame accent
_SPARKS_C_CYAN=$'\033[38;5;75m'
_SPARKS_C_GREEN=$'\033[38;5;114m'
_SPARKS_C_YELLOW=$'\033[38;5;221m'
_SPARKS_C_RED=$'\033[38;5;204m'
_SPARKS_C_GREY=$'\033[38;5;243m'
_SPARKS_C_WHITE=$'\033[38;5;252m'

# Synthwave / Particle Colors
_SPARKS_C_PURP_L=$'\033[38;5;171m'
_SPARKS_C_CYAN_M=$'\033[38;5;81m'
_SPARKS_C_PURP_D=$'\033[38;5;93m'

# Logo triad (pink / cyan / lavender)
_SPARKS_C_LOGO_PINK=$'\033[38;5;201m'
_SPARKS_C_LOGO_CYAN=$'\033[38;5;51m'
_SPARKS_C_LOGO_LAVEN=$'\033[38;5;141m'

# The spark icon — *.+ with logo triad colours (compact, for inline banner use)
_SPARKS_ICON="${_SPARKS_C_LOGO_PINK}*${_SPARKS_C_LOGO_CYAN}.${_SPARKS_C_LOGO_LAVEN}+${_SPARKS_C_RESET}"

# Per-letter colored SPARKS label for banner (S=pink P=cyan A=lav R=pink K=cyan S=lav)
_SPARKS_LABEL="${_SPARKS_C_LOGO_PINK}S${_SPARKS_C_LOGO_CYAN}P${_SPARKS_C_LOGO_LAVEN}A${_SPARKS_C_LOGO_PINK}R${_SPARKS_C_LOGO_CYAN}K${_SPARKS_C_LOGO_LAVEN}S${_SPARKS_C_RESET}"

# Single-line logo — *.+ SPARKS -- Persona Manager (for standalone header displays)
# SPARKS letter colours cycle per-letter: S=pink P=cyan A=lav R=pink K=cyan S=lav
_SPARKS_LOGO_LINE="${_SPARKS_C_LOGO_PINK}*${_SPARKS_C_LOGO_CYAN}.${_SPARKS_C_LOGO_LAVEN}+${_SPARKS_C_RESET}  ${_SPARKS_C_LOGO_PINK}S${_SPARKS_C_LOGO_CYAN}P${_SPARKS_C_LOGO_LAVEN}A${_SPARKS_C_LOGO_PINK}R${_SPARKS_C_LOGO_CYAN}K${_SPARKS_C_LOGO_LAVEN}S${_SPARKS_C_RESET} ${_SPARKS_C_DIM}--${_SPARKS_C_RESET} ${_SPARKS_C_LOGO_CYAN}Persona${_SPARKS_C_RESET} ${_SPARKS_C_LOGO_LAVEN}Manager${_SPARKS_C_RESET}"

# ---------------------------------------------------------------------------
# _sparks_banner — Compact one-line status shown on cd
#
# Format:
#   *.+ sparks: base + sysadmin  (from ~/.sparks, ~/digital/ai/dgs/.sparks)
#   *.+ sparks: base + sysadmin  [stale — run: sparks apply]
#
# Only prints if SPARKS_CD_BANNER is "true".
# ---------------------------------------------------------------------------

_sparks_banner() {
  local dir="${1:-$PWD}"
  [[ "${SPARKS_CD_BANNER:-true}" == "true" ]] || return 0

  local -a persona_names=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && persona_names+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  # Build persona list string
  local persona_str=""
  for name in "${persona_names[@]}"; do
    [[ -n "${persona_str}" ]] && persona_str+=" + "
    if [[ "${name}" == "base" ]]; then
      persona_str+="${_SPARKS_C_GREY}base${_SPARKS_C_RESET}"
    else
      persona_str+="${_SPARKS_C_WHITE}${_SPARKS_C_BOLD}${name}${_SPARKS_C_RESET}"
    fi
  done

  # Build source hint
  local -a chain_files=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && chain_files+=("${f}")
  done < <(_sparks_inheritance_chain "${dir}")

  local source_hint=""
  if (( ${#chain_files[@]} > 0 )); then
    local -a short_paths=()
    for f in "${chain_files[@]}"; do
      # Shorten paths: replace $HOME with ~
      local short="${f/#${HOME}/\~}"
      # Remove the /.sparks suffix for cleaner display
      short="${short%/.sparks}"
      short_paths+=("${short}")
    done
    source_hint="${_SPARKS_C_GREY}(${short_paths[*]})${_SPARKS_C_RESET}"
  fi

  # Staleness check — any active adapter needing attention triggers the hint
  local stale_hint=""
  if [[ "${SPARKS_STALE_HINT:-true}" == "true" ]]; then
    local target_dir
    target_dir=$(_sparks_find_target_dir "${dir}")
    if [[ -n "${target_dir}" ]]; then
      local any_stale=0
      for adapter in "${SPARKS_ACTIVE_ADAPTERS[@]}"; do
        _sparks_load_adapter "${adapter}" 2>/dev/null || continue
        if _sparks_adapter_check_stale "${adapter}" "${target_dir}" "${dir}"; then
          any_stale=1
          break
        fi
      done
      if (( any_stale )); then
        stale_hint=" ${_SPARKS_C_YELLOW}[stale — run: ${_SPARKS_C_LOGO_CYAN}sparks apply${_SPARKS_C_YELLOW}]${_SPARKS_C_RESET}"
      fi
    fi
  fi

  printf '%b %b: %s  %s%s\n' \
    "${_SPARKS_ICON}" "${_SPARKS_LABEL}" "${persona_str}" "${source_hint}" "${stale_hint}"
}

# ---------------------------------------------------------------------------
# _sparks_find_target_dir — Find the directory where AGENTS.md should live
#
# Logic: if we're inside a git repo, use the git root.
# Otherwise, use $PWD.
# ---------------------------------------------------------------------------

_sparks_find_target_dir() {
  local dir="${1:-$PWD}"
  local git_root
  git_root=$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "${git_root}" ]]; then
    echo "${git_root}"
  else
    echo "${dir}"
  fi
}

# ---------------------------------------------------------------------------
# _sparks_status — Detailed status display
#
# Shows:
#   - Active personas with descriptions
#   - Inheritance chain
#   - Available (inactive) personas
#   - Staleness of AGENTS.md
# ---------------------------------------------------------------------------

_sparks_status() {
  local dir="${1:-$PWD}"

  local -a active=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && active+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  local -a available=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && available+=("${name}")
  done < <(_sparks_list_available)

  # 3-row banner: logo (*. * / * / blank) on the left (8-char column),
  # SPARKS pixel font on the right. Letter colours cycle: S=pink P=cyan A=lav R=pink K=cyan S=lav
  printf '\n'
  printf '  %b*%b.%b %b*%b  %b▄▀▀%b %b█▀▄%b %b▄▀▄%b %b█▀▄%b %b█▄▀%b %b▄▀▀%b\n' \
    "${_SPARKS_C_LOGO_PINK}" "${_SPARKS_C_LOGO_CYAN}" \
    "${_SPARKS_C_RESET}" "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}"
  printf '    %b*%b   %b ▀▄%b %b█▀ %b %b█▀█%b %b█▀▄%b %b█ █%b %b ▀▄%b\n' \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}"
  printf '        %b▀▀ %b %b▀  %b %b▀ ▀%b %b▀ ▀%b %b▀ ▀%b %b▀▀ %b\n' \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_PINK}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_CYAN}"  "${_SPARKS_C_RESET}" \
    "${_SPARKS_C_LOGO_LAVEN}" "${_SPARKS_C_RESET}"

  printf '  %b──────────────────────────────────────%b\n\n' \
    "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}"

  # Active personas
  printf '  %b%sActive personas:%b\n' "${_SPARKS_C_BOLD}" "${_SPARKS_C_CYAN}" "${_SPARKS_C_RESET}"
  for name in "${active[@]}"; do
    local desc
    desc=$(_sparks_read_persona_meta "${name}" "description" 2>/dev/null) || desc=""
    if _sparks_persona_exists "${name}"; then
      printf '    %b✔%b  %-16s %b%s%b\n' \
        "${_SPARKS_C_GREEN}" "${_SPARKS_C_RESET}" \
        "${name}" \
        "${_SPARKS_C_GREY}" "${desc}" "${_SPARKS_C_RESET}"
    else
      printf '    %b✗%b  %-16s %b(not found in central store)%b\n' \
        "${_SPARKS_C_RED}" "${_SPARKS_C_RESET}" \
        "${name}" \
        "${_SPARKS_C_RED}" "${_SPARKS_C_RESET}"
    fi
  done

  # Inheritance chain
  local -a chain_files=()
  while IFS= read -r f; do
    [[ -n "${f}" ]] && chain_files+=("${f}")
  done < <(_sparks_inheritance_chain "${dir}")

  if (( ${#chain_files[@]} > 0 )); then
    printf '\n  %b%sInheritance chain:%b\n' "${_SPARKS_C_BOLD}" "${_SPARKS_C_CYAN}" "${_SPARKS_C_RESET}"
    for f in "${chain_files[@]}"; do
      local short="${f/#${HOME}/\~}"
      local -a file_personas=()
      while IFS= read -r p; do
        [[ -n "${p}" ]] && file_personas+=("${p}")
      done < <(_sparks_read_sparks_file "${f}")
      printf '    %b▸%b  %s  %b→  %s%b\n' \
        "${_SPARKS_C_SPARK}" "${_SPARKS_C_RESET}" \
        "${short}" \
        "${_SPARKS_C_GREY}" "${file_personas[*]}" "${_SPARKS_C_RESET}"
    done
  fi

  # Available (inactive) personas
  local -a inactive=()
  local -A active_set=()
  for name in "${active[@]}"; do
    active_set["${name}"]=1
  done
  for name in "${available[@]}"; do
    [[ -z "${active_set[${name}]+_}" ]] && inactive+=("${name}")
  done

  if (( ${#inactive[@]} > 0 )); then
    printf '\n  %b%sAvailable (inactive):%b\n' "${_SPARKS_C_BOLD}" "${_SPARKS_C_CYAN}" "${_SPARKS_C_RESET}"
    for name in "${inactive[@]}"; do
      local desc
      desc=$(_sparks_read_persona_meta "${name}" "description" 2>/dev/null) || desc=""
      printf '    %b○%b  %-16s %b%s%b\n' \
        "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}" \
        "${name}" \
        "${_SPARKS_C_GREY}" "${desc}" "${_SPARKS_C_RESET}"
    done
  fi

  # Context file status — loop over all active adapters
  local target_dir
  target_dir=$(_sparks_find_target_dir "${dir}")
  if [[ -n "${target_dir}" ]]; then
    printf '\n  %b%sContext files:%b\n' \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_CYAN}" "${_SPARKS_C_RESET}"

    for adapter in "${SPARKS_ACTIVE_ADAPTERS[@]}"; do
      _sparks_load_adapter "${adapter}" 2>/dev/null || continue

      local file_fn="_sparks_adapter_${adapter}_file"
      declare -f "${file_fn}" &>/dev/null || continue

      local filename
      filename=$("${file_fn}")
      local target_file="${target_dir}/${filename}"
      local display_path="${target_file/#${HOME}/\~}"

      if _sparks_adapter_check_stale "${adapter}" "${target_dir}" "${dir}"; then
        if [[ ! -f "${target_file}" ]]; then
          printf '    %b○%b  %-38s  %b[not yet created — run: %bsparks apply%b]%b\n' \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}" \
            "${display_path}" \
            "${_SPARKS_C_GREY}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}"
        else
          # Bootstrap adapters have their own _is_stale fn (no sentinel)
          local is_stale_fn="_sparks_adapter_${adapter}_is_stale"
          if declare -f "${is_stale_fn}" &>/dev/null; then
            printf '    %b!%b  %-38s  %b[not set up — run: %bsparks apply%b]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
          else
            printf '    %b!%b  %-38s  %b[stale — run: %bsparks apply%b]%b\n' \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}" \
              "${display_path}" \
              "${_SPARKS_C_YELLOW}" "${_SPARKS_C_LOGO_CYAN}" "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
          fi
        fi
      else
        # Build version summary from embedded persona-version comments
        local version_summary=""
        if [[ -f "${target_file}" ]]; then
          version_summary=$(grep '<!-- persona-version:' "${target_file}" \
            | sed 's/.*persona-version: \(.*\) -->/\1/' \
            | tr '\n' ' ' \
            | sed 's/ $//')
          [[ -n "${version_summary}" ]] \
            && version_summary="[current — personas: ${version_summary}]" \
            || version_summary="[current]"
        fi
        printf '    %b✔%b  %-38s  %b%s%b\n' \
          "${_SPARKS_C_GREEN}" "${_SPARKS_C_RESET}" \
          "${display_path}" \
          "${_SPARKS_C_GREEN}" "${version_summary}" "${_SPARKS_C_RESET}"
      fi
    done
  fi

  printf '\n'
}

# ---------------------------------------------------------------------------
# _sparks_menu — Interactive fzf persona selector
#
# Shows active and available personas with toggle support.
# Returns selected persona names (newline-separated).
# ---------------------------------------------------------------------------

_sparks_menu() {
  local dir="${1:-$PWD}"

  local -a active=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && active+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  local -a available=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && available+=("${name}")
  done < <(_sparks_list_available)

  local -A active_set=()
  for name in "${active[@]}"; do
    active_set["${name}"]=1
  done

  if command -v fzf &>/dev/null; then
    _sparks_menu_fzf "${dir}"
  else
    _sparks_menu_basic "${dir}"
  fi
}

_sparks_menu_fzf() {
  local dir="$1"

  local -a active=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && active+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  local -a available=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && available+=("${name}")
  done < <(_sparks_list_available)

  local -A active_set=()
  for name in "${active[@]}"; do
    active_set["${name}"]=1
  done

  local -a entries=()
  for name in "${available[@]}"; do
    [[ "${name}" == "base" ]] && continue  # base cannot be toggled
    local desc
    desc=$(_sparks_read_persona_meta "${name}" "description" 2>/dev/null) || desc=""
    local status_icon="○"
    local status_word="inactive"
    if [[ -n "${active_set[${name}]+_}" ]]; then
      status_icon="●"
      status_word="active"
    fi
    entries+=("$(printf '%s\t%s  %-16s  %-8s  %s' \
      "${name}" "${status_icon}" "${name}" "${status_word}" "${desc}")")
  done

  local selected
  selected=$(printf '%s\n' "${entries[@]}" |
    fzf --delimiter=$'\t' \
      --with-nth=2 \
      --header=$'  \033[38;5;201m*\033[38;5;51m.\033[38;5;141m+\033[0m  \033[38;5;201mS\033[38;5;51mP\033[38;5;141mA\033[38;5;201mR\033[38;5;51mK\033[38;5;141mS\033[0m \033[2m--\033[0m \033[38;5;51mPersona\033[0m \033[38;5;141mManager\033[0m\n  Toggle personas  (TAB to select, ENTER to apply)\n  base is always active and cannot be toggled.\n' \
      --prompt='  sparks ❯ ' \
      --height=~50% \
      --layout=reverse \
      --border=rounded \
      --multi \
      --color='header:blue,prompt:#d7875f,pointer:green,marker:green,border:dim' \
      --pointer='▸' \
      --marker='✔')

  [[ -z "${selected}" ]] && return 1

  # Extract persona names from selection
  echo "${selected}" | cut -f1
}

_sparks_menu_basic() {
  local dir="$1"

  local -a available=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && available+=("${name}")
  done < <(_sparks_list_available)

  local -a active=()
  while IFS= read -r name; do
    [[ -n "${name}" ]] && active+=("${name}")
  done < <(_sparks_resolve_personas "${dir}")

  local -A active_set=()
  for name in "${active[@]}"; do
    active_set["${name}"]=1
  done

  # Filter out base
  local -a toggleable=()
  for name in "${available[@]}"; do
    [[ "${name}" != "base" ]] && toggleable+=("${name}")
  done

  printf '\n  %b\n  %bToggle personas%b\n' "${_SPARKS_LOGO_LINE}" "${_SPARKS_C_GREY}" "${_SPARKS_C_RESET}"
  printf '  base is always active and cannot be toggled.\n\n'

  local i=1
  for name in "${toggleable[@]}"; do
    local desc
    desc=$(_sparks_read_persona_meta "${name}" "description" 2>/dev/null) || desc=""
    local status_icon="○"
    [[ -n "${active_set[${name}]+_}" ]] && status_icon="●"
    printf '    %d) %s  %-16s  %s\n' "${i}" "${status_icon}" "${name}" "${desc}"
    (( i++ ))
  done

  printf '\n'
  local choice
  read -rp "  Select (comma-separated numbers, or q to cancel): " choice
  [[ "${choice}" == "q" || -z "${choice}" ]] && return 1

  IFS=',' read -ra selections <<< "${choice}"
  for sel in "${selections[@]}"; do
    sel="${sel#"${sel%%[! ]*}"}"
    sel="${sel%"${sel##*[! ]}"}"
    if [[ "${sel}" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#toggleable[@]} )); then
      echo "${toggleable[$(( sel - 1 ))]}"
    fi
  done
}

# ---------------------------------------------------------------------------
# _sparks_session_info — Print persona landscape and OpenCode session instructions
#
# Displays the current persona state (reuses _sparks_status) then prints
# instructions on how to launch an AI-guided persona management session
# via the custom OpenCode agent + /sparks command.
# ---------------------------------------------------------------------------

_sparks_session_info() {
  local dir="${1:-$PWD}"

  # Session instructions
  local opencode_agents_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"
  local opencode_cmds_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/commands"

  printf '  %b%sAI Persona Session:%b\n\n' \
    "${_SPARKS_C_BOLD}" "${_SPARKS_C_CYAN}" "${_SPARKS_C_RESET}"

  if [[ -f "${opencode_agents_dir}/sparks.md" && -f "${opencode_cmds_dir}/sparks.md" ]]; then
    printf '    %b1.%b  Launch OpenCode:         %bopencode%b\n' \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}" \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}"
    printf '    %b2.%b  Switch to Sparks agent:  %bTab%b → select %bsparks%b\n' \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}" \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}" \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}"
    printf '    %b3.%b  Run the command:          %b/sparks%b [describe what you want]\n' \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}" \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}"
    printf '\n'
    printf '    The Sparks agent will read your persona landscape, recommend\n'
    printf '    edits or new personas, make the changes, and run %bsparks apply%b.\n\n' \
      "${_SPARKS_C_BOLD}" "${_SPARKS_C_RESET}"
  else
    printf '    %b!%b  OpenCode agent/command not found.\n' \
      "${_SPARKS_C_YELLOW}" "${_SPARKS_C_RESET}"
    printf '    Expected:\n'
    printf '      %s\n' "${opencode_agents_dir/#${HOME}/\~}/sparks.md"
    printf '      %s\n' "${opencode_cmds_dir/#${HOME}/\~}/sparks.md"
    printf '\n'
  fi
}

# ---------------------------------------------------------------------------
# _sparks_show_help — Print help text
# ---------------------------------------------------------------------------

_sparks_show_help() {
  cat <<HELP

  ${_SPARKS_LOGO_LINE}

  ${_SPARKS_C_BOLD}USAGE${_SPARKS_C_RESET}
    sparks                          Show current status
    sparks on <name> [name...]      Activate persona(s) in \$PWD
    sparks off [name...]            Deactivate; no args = clear .sparks
    sparks menu                     Interactive persona selector
    sparks apply [--all]            Regenerate AI context files (AGENTS.md, CLAUDE.md, ...)
    sparks list                     List all available personas
    sparks show [name]              Print merged content (no arg = all active)
    sparks new <name>               Create new persona from template
    sparks edit                     AI-guided persona management via OpenCode
    sparks diff                     Show if context files are out of date
    sparks doctor [fix]             Check system health; fix applies safe fixes
    sparks sync push                chezmoi add + commit + push
    sparks sync pull                chezmoi pull + apply
    sparks help                     Show this help

  ${_SPARKS_C_BOLD}DIRECTORY INHERITANCE${_SPARKS_C_RESET}
    Place a .sparks file with persona names (one per line) in any directory.
    Sparks walks upward from \$PWD to \$HOME, merging all .sparks files.
    Prefix a name with - to exclude an inherited persona.
    base is always active and cannot be excluded.

  ${_SPARKS_C_BOLD}SENTINEL PROTOCOL${_SPARKS_C_RESET}
    sparks apply writes between <!-- sparks:begin --> and <!-- sparks:end -->
    markers in AGENTS.md (and other tool files).  Content outside these
    markers is never touched.

  ${_SPARKS_C_BOLD}CONFIGURATION${_SPARKS_C_RESET}
    Central store:    ~/.config/sparks/personas/
    Config:           ~/.config/sparks/sparks.conf
    Per-dir state:    .sparks (commit to version control)

HELP
}
