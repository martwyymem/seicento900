#!/usr/bin/env bash
# Release gate: every check a release needs, run on a clean copy of HEAD (council review 2026-11-23).
#
#   tools/release_gate.sh                # all steps, both exports
#   tools/release_gate.sh --no-export    # tests only (quick pre-commit check)
#   tools/release_gate.sh --out DIR      # keep the build copy, logs and exports in DIR
#
# Steps (each must pass; the script stops at the first failure and exits 1):
#   1. copy:    the working godot/ (for the gitignored .godot cache, .import files and fetched art), then
#               `git archive HEAD godot` over it, then delete files that are untracked but not ignored, so
#               uncommitted edits from other threads never reach the build
#   2. import:  godot --headless --import (retried once: the first import of a fresh copy can segfault 4.7.2)
#   3. boot:    godot --headless --quit-after 60, with no SCRIPT ERROR / Parse Error in the log
#   4. suite:   tests/run_tests.gd
#   5. qa:      tests/run_qa.gd (suites outside run_tests.gd)
#   6. parity:  tests/_run_race_test.gd (completed=true errors=0)
#   7. export:  the "Windows Desktop" and "macOS" presets, release mode
#
# The tests run with HOME pointed at a scratch folder, so user:// (saves, caches, dev_sandbox) is the gate's
# own and never the player's or another worktree's. The exports use the real HOME (export templates).
# A GitHub runner cannot do this: the fetched art and most .import settings are gitignored and local.
set -u -o pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
EXPORT=1
OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--no-export) EXPORT=0 ;;
		--out) OUT="$2"; shift ;;
		-h|--help) sed -n '2,22p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

SHA="$(git -C "$REPO" rev-parse --short HEAD)"
OUT="${OUT:-${TMPDIR:-/tmp}/seicento_gate_$SHA}"
WORK="$OUT/godot"
LOGS="$OUT/logs"
GATE_HOME="$OUT/home"
TIMEOUT="$(command -v gtimeout || command -v timeout || true)"

mkdir -p "$LOGS" "$GATE_HOME"
RESULTS=()
START=$(date +%s)

say() { printf '\n== %s\n' "$*"; }
finish() {
	echo
	echo "Release gate for $SHA ($(( $(date +%s) - START )) s):"
	for r in "${RESULTS[@]}"; do echo "  $r"; done
	echo "Logs: $LOGS"
	exit "$1"
}
# run NAME LIMIT_S CMD...: runs CMD in the build copy, logs it, records pass/fail.
run() {
	local name="$1" limit="$2"; shift 2
	local log="$LOGS/$name.log" t0=$(date +%s) code
	say "$name: $*"
	if [ -n "$TIMEOUT" ]; then
		(cd "$WORK" && "$TIMEOUT" -k 10 "$limit" "$@") >"$log" 2>&1
	else
		(cd "$WORK" && "$@") >"$log" 2>&1
	fi
	code=$?
	tail -n 4 "$log"
	if [ $code -ne 0 ]; then
		[ $code -eq 124 ] && echo "(timed out after $limit s)"
		RESULTS+=("FAIL $name (exit $code, $(( $(date +%s) - t0 )) s)")
		return 1
	fi
	RESULTS+=("ok   $name ($(( $(date +%s) - t0 )) s)")
}
fail_now() { RESULTS+=("FAIL $1"); finish 1; }

if [ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]; then
	echo "note: the working tree has uncommitted changes; the gate checks HEAD ($SHA) without them."
fi

# 1. clean copy of HEAD
say "copy: HEAD $SHA -> $WORK"
mkdir -p "$WORK"
rsync -a --delete "$REPO/godot/" "$WORK/" || fail_now "copy (rsync)"
(cd "$REPO" && git archive HEAD godot) | tar -x -C "$OUT" || fail_now "copy (git archive)"
# files the working tree has untracked and not ignored are someone's work in progress: drop them
(cd "$REPO" && git ls-files -o --exclude-standard -- godot) | sed 's|^godot/||' | while IFS= read -r f; do
	rm -f "$WORK/$f"
done
RESULTS+=("ok   copy")

# 2. import (retry once)
if ! HOME="$GATE_HOME" run import 900 "$GODOT" --headless --path . --import; then
	unset 'RESULTS[${#RESULTS[@]}-1]'
	HOME="$GATE_HOME" run import-retry 900 "$GODOT" --headless --path . --import || finish 1
fi

# 3. boot
HOME="$GATE_HOME" run boot 180 "$GODOT" --headless --path . --quit-after 60 || finish 1
if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LOGS/boot.log"; then
	grep -nE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LOGS/boot.log" | head -5
	unset 'RESULTS[${#RESULTS[@]}-1]'
	fail_now "boot (script errors in the log)"
fi

# 4-6. tests
HOME="$GATE_HOME" run suite 2400 "$GODOT" --headless --path . -s tests/run_tests.gd || finish 1
HOME="$GATE_HOME" run qa 900 "$GODOT" --headless --path . -s tests/run_qa.gd || finish 1
HOME="$GATE_HOME" run parity 900 "$GODOT" --headless --path . -s tests/_run_race_test.gd || finish 1
grep -q 'completed=true errors=0' "$LOGS/parity.log" || fail_now "parity (no 'completed=true errors=0')"

# 7. exports
if [ $EXPORT -eq 1 ]; then
	mkdir -p "$OUT/build"
	run export-windows 1800 "$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/build/seicento.exe" || finish 1
	[ -s "$OUT/build/seicento.exe" ] || fail_now "export-windows (no exe written)"
	run export-macos 1800 "$GODOT" --headless --path . --export-release "macOS" "$OUT/build/Seicento.app" || finish 1
	[ -d "$OUT/build/Seicento.app" ] || fail_now "export-macos (no app written)"
	RESULTS+=("     exe $(du -h "$OUT/build/seicento.exe" | cut -f1), app $(du -sh "$OUT/build/Seicento.app" | cut -f1)")
else
	RESULTS+=("skip export (--no-export)")
fi

finish 0
