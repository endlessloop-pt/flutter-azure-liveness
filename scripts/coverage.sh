#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# scripts/coverage.sh
#
# Run Dart unit tests with coverage, generate an HTML report, and enforce a
# minimum line-coverage threshold.
#
# Usage:
#   ./scripts/coverage.sh [--threshold <pct>] [--open]
#
# Options:
#   --threshold <pct>   Minimum required line coverage, 0-100 (default: 80)
#   --open              Open the HTML report in the default browser after build
#
# Requirements:
#   - flutter (on PATH)
#   - lcov  (brew install lcov  /  apt install lcov)
#   - genhtml (included with lcov)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

THRESHOLD=80
OPEN=0

# ── Parse arguments ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      THRESHOLD="$2"; shift 2 ;;
    --open)
      OPEN=1; shift ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

LCOV_FILE="coverage/lcov.info"
HTML_DIR="coverage/html"

# ── Run tests ─────────────────────────────────────────────────────────────────
echo "▶ Running flutter test --coverage …"
flutter test --coverage

if [[ ! -f "$LCOV_FILE" ]]; then
  echo "✗ Coverage data not found at $LCOV_FILE" >&2
  exit 1
fi

# ── Generate HTML report ──────────────────────────────────────────────────────
echo "▶ Generating HTML report → $HTML_DIR"
genhtml "$LCOV_FILE" \
  --output-directory "$HTML_DIR" \
  --title "flutter_azure_liveness coverage" \
  --quiet

# ── Parse coverage percentage ─────────────────────────────────────────────────
SUMMARY=$(lcov --summary "$LCOV_FILE" 2>&1)

LINES_PCT=$(echo "$SUMMARY" \
  | grep -E "lines\.*:" \
  | grep -oE "[0-9]+\.[0-9]+" \
  | head -1)

if [[ -z "$LINES_PCT" ]]; then
  echo "✗ Could not parse line coverage from lcov summary." >&2
  echo "$SUMMARY" >&2
  exit 1
fi

# Truncate to integer for comparison
LINES_INT=$(printf "%.0f" "$LINES_PCT")

echo ""
echo "────────────────────────────────────────"
echo "  Line coverage : ${LINES_PCT}%"
echo "  Threshold     : ${THRESHOLD}%"
echo "  HTML report   : ${HTML_DIR}/index.html"
echo "────────────────────────────────────────"

# ── Enforce threshold ─────────────────────────────────────────────────────────
if (( LINES_INT < THRESHOLD )); then
  echo ""
  echo "✗ Coverage ${LINES_PCT}% is below the required ${THRESHOLD}%." >&2
  exit 1
else
  echo ""
  echo "✓ Coverage check passed (${LINES_PCT}% ≥ ${THRESHOLD}%)"
fi

# ── Optionally open the report ────────────────────────────────────────────────
if [[ "$OPEN" -eq 1 ]]; then
  if command -v open &>/dev/null; then
    open "${HTML_DIR}/index.html"
  elif command -v xdg-open &>/dev/null; then
    xdg-open "${HTML_DIR}/index.html"
  fi
fi
