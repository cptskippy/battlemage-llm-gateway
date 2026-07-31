#!/usr/bin/env bash
# =============================================================================
# Check for updates to all components installed by scripts 01–04.
#
# Compares currently installed versions against the latest available release
# for each component and reports whether an update is available.
#
# Run with: bash check-updates.sh
# =============================================================================

set -euo pipefail

# ── Colour helpers (degrade gracefully if not a terminal) ────────────────────

if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

info()  { echo -e "  ${CYAN}$*${RESET}"; }
ok()    { echo -e "  ${GREEN}[up to date]${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}[update available]${RESET} $1 → ${BOLD}$2${RESET}"; }
fail()  { echo -e "  ${RED}[not installed]${RESET} $*"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but not found." >&2
    exit 1
  }
}

# Fetch the latest GitHub release tag for a repo.
# Usage: latest_github_release owner/repo
latest_github_release() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d '"' -f 4 || echo "(unknown)"
}

# Fetch the latest npm version for a package.
# Usage: latest_npm_version package-name
latest_npm_version() {
  npm view "$1" version 2>/dev/null || echo "(unknown)"
}

# Strip leading 'v' from a version string.
strip_v() {
  echo "${1#v}"
}

# Simple numeric version comparison: returns 0 if $1 >= $2.
# Works for dotted versions like 1.2.3.  Not perfect but good enough.
version_gte() {
  # If either is unknown or empty, assume up to date
  [[ -z "$1" || -z "$2" ]] && return 0
  [[ "$1" == "(unknown)" || "$2" == "(unknown)" ]] && return 0

  # Use sort -V for natural version ordering
  local latest
  latest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
  [ "$latest" = "$1" ]
}

# ── Require tools ─────────────────────────────────────────────────────────────

require_cmd curl
require_cmd jq

# ── Banner ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}=============================================================${RESET}"
echo -e "${BOLD}  Update check — llm-gateway components${RESET}"
echo -e "${BOLD}=============================================================${RESET}"
echo ""

updates_available=0

# ── 1. linux-firmware (git repo, script 01) ───────────────────────────────────

echo -e "${BOLD}linux-firmware${RESET} (git: git.kernel.org/.../linux-firmware)"

INSTALLED_FW=""
if [ -d /lib/firmware/xe ]; then
  BLOB_COUNT=$(ls /lib/firmware/xe/bmg_*.bin 2>/dev/null | wc -l)
  INSTALLED_FW="installed ($BLOB_COUNT Battlemage blob(s))"
fi

# linux-firmware is a git.kernel.org repo — check latest commit date
LATEST_FW_DATE=$(curl -fsSL "https://git.kernel.org/cgit/linux/kernel/git/firmware/linux-firmware.git/plain/HEAD" 2>/dev/null | head -1 || true)

if [ -n "$INSTALLED_FW" ]; then
  ok "$INSTALLED_FW"
  info "Source: https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
  info "Re-run script 01 to update from latest commit"
else
  fail "linux-firmware (no /lib/firmware/xe directory)"
fi

echo ""

# ── 2. Intel compute-runtime (GitHub releases, script 02) ────────────────────

echo -e "${BOLD}Intel compute-runtime${RESET} (github: intel/compute-runtime)"

INSTALLED_CR=$(dpkg -l libze-intel-gpu1 2>/dev/null | awk '/^ii/{print $3}' | head -1 | cut -d'-' -f1 || true)
LATEST_CR=$(latest_github_release "intel/compute-runtime")

if [ -n "$INSTALLED_CR" ]; then
  INSTALLED_CR_MAJOR=$(echo "$INSTALLED_CR" | cut -d'.' -f1-2)
  LATEST_CR_MAJOR=$(echo "$LATEST_CR" | cut -d'.' -f1-2)

  if [[ "$INSTALLED_CR_MAJOR" == "$LATEST_CR_MAJOR" ]]; then
    ok "Installed: $INSTALLED_CR | Latest: $LATEST_CR"
  else
    warn "Installed: $INSTALLED_CR" "$LATEST_CR"
    updates_available=1
  fi
else
  fail "Intel compute-runtime"
  info "Latest available: $LATEST_CR"
fi

echo ""

# ── 3. Intel Graphics Compiler / IGC (GitHub releases, script 02) ────────────

echo -e "${BOLD}Intel Graphics Compiler (IGC)${RESET} (github: intel/intel-graphics-compiler)"

INSTALLED_IGC=$(dpkg -l intel-igc-core-2 2>/dev/null | awk '/^ii/{print $3}' | head -1 || true)
LATEST_IGC=$(latest_github_release "intel/intel-graphics-compiler")

if [ -n "$INSTALLED_IGC" ]; then
  INSTALLED_IGC_MAJOR=$(echo "$INSTALLED_IGC" | cut -d'.' -f1-2)
  LATEST_IGC_MAJOR=$(strip_v "$(echo "$LATEST_IGC" | cut -d'.' -f1-2)")

  if version_gte "$INSTALLED_IGC_MAJOR" "$LATEST_IGC_MAJOR"; then
    ok "Installed: $INSTALLED_IGC | Latest: $LATEST_IGC"
  else
    warn "Installed: $INSTALLED_IGC" "$LATEST_IGC"
    updates_available=1
  fi
else
  fail "Intel Graphics Compiler (IGC)"
  info "Latest available: $LATEST_IGC"
fi

echo ""

# ── 4. Level Zero loader (GitHub releases, script 02) ────────────────────────

echo -e "${BOLD}Level Zero loader${RESET} (github: oneapi-src/level-zero)"

INSTALLED_ZE=$(dpkg -l libze1 2>/dev/null | awk '/^ii/{print $3}' | head -1 || true)
LATEST_ZE=$(strip_v "$(latest_github_release "oneapi-src/level-zero")")

if [ -n "$INSTALLED_ZE" ]; then
  # Installed version may have a suffix like +u24.04; strip it for comparison
  INSTALLED_ZE_BASE=$(echo "$INSTALLED_ZE" | cut -d'+' -f1)

  if version_gte "$INSTALLED_ZE_BASE" "$LATEST_ZE"; then
    ok "Installed: $INSTALLED_ZE | Latest: $LATEST_ZE"
  else
    warn "Installed: $INSTALLED_ZE" "$LATEST_ZE"
    updates_available=1
  fi
else
  fail "Level Zero loader"
  info "Latest available: $LATEST_ZE"
fi

echo ""

# ── 5. llama.cpp (git repo, built from source, script 02) ────────────────────

echo -e "${BOLD}llama.cpp${RESET} (github: ggml-org/llama.cpp — built from source)"

LLAMA_DIR="${HOME}/llama.cpp"
LATEST_LLAMA=$(latest_github_release "ggml-org/llama.cpp")

if [ -d "$LLAMA_DIR" ] && [ -d "$LLAMA_DIR/.git" ]; then
  CURRENT_LLAMA=$(cd "$LLAMA_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "(no tag)")

  # Detect default branch (main or master)
  LLAMA_DEFAULT_BRANCH=""
  if git -C "$LLAMA_DIR" rev-parse origin/main >/dev/null 2>&1; then
    LLAMA_DEFAULT_BRANCH="origin/main"
  elif git -C "$LLAMA_DIR" rev-parse origin/master >/dev/null 2>&1; then
    LLAMA_DEFAULT_BRANCH="origin/master"
  fi

  # Fetch latest to compare (may take a moment)
  FETCH_OK=false
  if [ -n "$LLAMA_DEFAULT_BRANCH" ] && git -C "$LLAMA_DIR" fetch --quiet origin 2>/dev/null; then
    FETCH_OK=true
  fi

  if $FETCH_OK && [ -n "$LLAMA_DEFAULT_BRANCH" ]; then
    CURRENT_HASH=$(git -C "$LLAMA_DIR" rev-parse HEAD 2>/dev/null || echo "")
    ORIGIN_HEAD=$(git -C "$LLAMA_DIR" rev-parse "$LLAMA_DEFAULT_BRANCH" 2>/dev/null || echo "")

    if [ -n "$ORIGIN_HEAD" ] && [ "$CURRENT_HASH" = "$ORIGIN_HEAD" ]; then
      ok "At: $CURRENT_LLAMA — up to date with $LLAMA_DEFAULT_BRANCH"
    else
      BEHIND=$(git -C "$LLAMA_DIR" rev-list --count HEAD.."$LLAMA_DEFAULT_BRANCH" 2>/dev/null || echo "?")
      warn "At: $CURRENT_LLAMA ($BEHIND commit(s) behind)" "Latest tag: $LATEST_LLAMA"
      updates_available=1
    fi
  else
    info "Could not fetch from origin — comparing tags only"
    if [ "$CURRENT_LLAMA" = "$LATEST_LLAMA" ]; then
      ok "At: $CURRENT_LLAMA"
    else
      warn "At: $CURRENT_LLAMA" "Latest tag: $LATEST_LLAMA"
      updates_available=1
    fi
  fi
else
  fail "llama.cpp (not found at $LLAMA_DIR)"
  info "Latest available: $LATEST_LLAMA"
fi

echo ""

# ── 6. llama-swap (GitHub releases, script 04) ───────────────────────────────

echo -e "${BOLD}llama-swap${RESET} (github: mostlygeek/llama-swap)"

SWAP_VERSION_FILE="${HOME}/.local/bin/llama-swap.version"
INSTALLED_SWAP=$(cat "$SWAP_VERSION_FILE" 2>/dev/null || true)
LATEST_SWAP=$(latest_github_release "mostlygeek/llama-swap")
# Strip leading 'v' for comparison
LATEST_SWAP_NUM=$(strip_v "$LATEST_SWAP")

if [ -n "$INSTALLED_SWAP" ]; then
  if version_gte "$INSTALLED_SWAP" "$LATEST_SWAP_NUM"; then
    ok "Installed: $INSTALLED_SWAP | Latest: $LATEST_SWAP"
  else
    warn "Installed: $INSTALLED_SWAP" "$LATEST_SWAP"
    updates_available=1
  fi
else
  fail "llama-swap"
  info "Latest available: $LATEST_SWAP"
fi

echo ""

# ── 7. opencode (npm package, script 04) ─────────────────────────────────────

echo -e "${BOLD}opencode${RESET} (npm: opencode-ai)"

if command -v opencode >/dev/null 2>&1; then
  INSTALLED_OC=$(opencode --version 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' || echo "(unknown)")
  LATEST_OC=$(latest_npm_version "opencode-ai")

  if [ "$LATEST_OC" != "(unknown)" ]; then
    if version_gte "$INSTALLED_OC" "$LATEST_OC"; then
      ok "Installed: $INSTALLED_OC | Latest: $LATEST_OC"
    else
      warn "Installed: $INSTALLED_OC" "$LATEST_OC"
      updates_available=1
    fi
  else
    ok "Installed: $INSTALLED_OC (could not check npm)"
  fi
else
  fail "opencode"
  LATEST_OC=$(latest_npm_version "opencode-ai")
  info "Latest available: $LATEST_OC"
fi

echo ""

# ── 8. pi coding agent (npm package, script 04) ──────────────────────────────

echo -e "${BOLD}pi coding agent${RESET} (npm: @mariozechner/pi-coding-agent)"

if command -v pi >/dev/null 2>&1; then
  INSTALLED_PI=$(pi -v 2>&1 | head -1 || echo "(unknown)")
  LATEST_PI=$(latest_npm_version "@mariozechner/pi-coding-agent")

  if [ "$LATEST_PI" != "(unknown)" ]; then
    if version_gte "$INSTALLED_PI" "$LATEST_PI"; then
      ok "Installed: $INSTALLED_PI | Latest: $LATEST_PI"
    else
      warn "Installed: $INSTALLED_PI" "$LATEST_PI"
      updates_available=1
    fi
  else
    ok "Installed: $INSTALLED_PI (could not check npm)"
  fi
else
  fail "pi coding agent"
  LATEST_PI=$(latest_npm_version "@mariozechner/pi-coding-agent")
  info "Latest available: $LATEST_PI"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}=============================================================${RESET}"
if [ "$updates_available" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  All components are up to date.${RESET}"
else
  echo -e "${YELLOW}${BOLD}  Some updates are available. Re-run the relevant scripts to upgrade.${RESET}"
fi
echo -e "${BOLD}=============================================================${RESET}"
echo ""

exit "$updates_available"
