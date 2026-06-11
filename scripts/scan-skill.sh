#!/usr/bin/env bash
#
# scan-skill.sh — manual SkillSpector wrapper for agent skills.
#
# Scans one skill (or every SKILL.md in the repo with --batch) using NVIDIA
# SkillSpector, writes a Markdown + JSON report per skill, and prints a
# colour-coded verdict based on risk_score.
#
# Usage:
#   scripts/scan-skill.sh <path|url>        Scan a single skill source
#                                           (directory, SKILL.md, git URL or zip).
#   scripts/scan-skill.sh --batch [root]    Scan every **/SKILL.md found under
#                                           root (default: SKILLS_ROOT / repo root).
#   scripts/scan-skill.sh -h | --help       Show this help.
#
# Environment overrides (all optional):
#   SKILLS_ROOT       Root used to discover skills in --batch (default: git repo
#                     root, or the current directory if not a git repo).
#   REPORT_DIR        Directory for generated reports (default: ./skillspector-reports).
#   RISK_THRESHOLD    risk_score at/above which a skill is flagged (default: 51).
#   SKILLSPECTOR_BIN  SkillSpector executable (default: skillspector).
#   SCAN_EXTRA_ARGS   Extra args appended to every scan (default: --no-llm).
#
# Exit code: 0 if every scanned skill is below RISK_THRESHOLD, 1 otherwise.

set -euo pipefail

# --- configuration (env-overridable) -----------------------------------------
REPO_ROOT_DEFAULT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SKILLS_ROOT="${SKILLS_ROOT:-$REPO_ROOT_DEFAULT}"
REPORT_DIR="${REPORT_DIR:-./skillspector-reports}"
RISK_THRESHOLD="${RISK_THRESHOLD:-51}"
SKILLSPECTOR_BIN="${SKILLSPECTOR_BIN:-skillspector}"
SCAN_EXTRA_ARGS="${SCAN_EXTRA_ARGS:---no-llm}"

# --- colours (disabled when not a TTY) ---------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_MAG=$'\033[35m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_RED=""; C_GRN=""; C_YEL=""; C_MAG=""; C_BOLD=""
fi

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

slugify() { echo "$1" | tr -c 'A-Za-z0-9._-' '_' | sed 's/__*/_/g;s/^_//;s/_$//'; }

die() { echo "${C_RED}error:${C_RESET} $*" >&2; exit 2; }

# --- read the risk assessment from a SkillSpector JSON report ----------------
# Prints "<score>\t<severity>\t<recommendation>". SkillSpector nests these
# under "risk_assessment"; the flat keys are kept as a fallback for older/newer
# output shapes.
read_assessment() {
  python3 - "$1" <<'PY' 2>/dev/null || printf '0\tUNKNOWN\t\n'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("0\tUNKNOWN\t"); raise SystemExit
ra = d.get("risk_assessment") or {}
score = ra.get("score", d.get("risk_score", 0))
sev = ra.get("severity", d.get("risk_severity", "UNKNOWN"))
rec = (ra.get("recommendation", d.get("risk_recommendation", "")) or "").replace("\t", " ").replace("\n", " ")
print(f"{score}\t{sev}\t{rec}")
PY
}

colour_for_severity() {
  case "$1" in
    CRITICAL) printf '%s' "$C_RED" ;;
    HIGH)     printf '%s' "$C_MAG" ;;
    MEDIUM)   printf '%s' "$C_YEL" ;;
    LOW)      printf '%s' "$C_GRN" ;;
    *)        printf '%s' "$C_RESET" ;;
  esac
}

# Scan one source; returns 0 if below threshold, 1 if flagged. Sets globals.
scan_one() {
  local source="$1"
  local scan_path="$source"

  # A SKILL.md file is scanned through its containing skill directory.
  if [ -f "$source" ] && [ "$(basename "$source")" = "SKILL.md" ]; then
    scan_path="$(dirname "$source")"
  fi

  local slug; slug="$(slugify "$source")"
  local md="$REPORT_DIR/${slug}.md"
  local json="$REPORT_DIR/${slug}.json"

  echo "${C_BOLD}Scanning${C_RESET} ${source}"
  # shellcheck disable=SC2086
  "$SKILLSPECTOR_BIN" scan "$scan_path" $SCAN_EXTRA_ARGS --format markdown --output "$md" || true
  # shellcheck disable=SC2086
  "$SKILLSPECTOR_BIN" scan "$scan_path" $SCAN_EXTRA_ARGS --format json --output "$json" || true

  local score severity recommendation
  IFS=$'\t' read -r score severity recommendation < <(read_assessment "$json")
  : "${score:=0}" "${severity:=UNKNOWN}"

  local col; col="$(colour_for_severity "$severity")"
  local verdict verdict_col rc
  if [ "${score%.*}" -ge "$RISK_THRESHOLD" ]; then
    verdict="FAIL"; verdict_col="$C_RED"; rc=1
  else
    verdict="PASS"; verdict_col="$C_GRN"; rc=0
  fi

  printf '  %srisk_score=%s%s  %sseverity=%s%s  ->  %s%s%s\n' \
    "$col" "$score" "$C_RESET" "$col" "$severity" "$C_RESET" \
    "$verdict_col$C_BOLD" "$verdict" "$C_RESET"
  [ -n "$recommendation" ] && printf '  %s\n' "$recommendation"
  printf '  report: %s\n\n' "$md"

  return "$rc"
}

# --- argument handling -------------------------------------------------------
[ "$#" -ge 1 ] || { usage; exit 2; }
case "$1" in
  -h|--help) usage; exit 0 ;;
esac

command -v "$SKILLSPECTOR_BIN" >/dev/null 2>&1 || die \
  "'$SKILLSPECTOR_BIN' not found. Install it: pip install \"skillspector @ git+https://github.com/NVIDIA/SkillSpector.git\""

mkdir -p "$REPORT_DIR"

failed=0
scanned=0

if [ "$1" = "--batch" ]; then
  root="${2:-$SKILLS_ROOT}"
  [ -d "$root" ] || die "batch root '$root' is not a directory"
  echo "${C_BOLD}Batch scan${C_RESET} under: $root"
  echo

  # Collect SKILL.md files (NUL-safe), prefer git when available for speed.
  mapfile -d '' -t skill_files < <(
    if git -C "$root" rev-parse >/dev/null 2>&1; then
      git -C "$root" ls-files -z -- '**/SKILL.md' 'SKILL.md' \
        | while IFS= read -r -d '' f; do printf '%s\0' "$root/$f"; done
    else
      find "$root" -type f -name SKILL.md -print0
    fi
  )

  if [ "${#skill_files[@]}" -eq 0 ]; then
    echo "${C_YEL}No SKILL.md files found under $root.${C_RESET}"
    exit 0
  fi

  for f in "${skill_files[@]}"; do
    scanned=$((scanned + 1))
    scan_one "$f" || failed=$((failed + 1))
  done
else
  scanned=1
  scan_one "$1" || failed=1
fi

echo "${C_BOLD}Summary:${C_RESET} scanned ${scanned}, flagged ${failed} (threshold >= ${RISK_THRESHOLD})."
[ "$failed" -eq 0 ] || exit 1
