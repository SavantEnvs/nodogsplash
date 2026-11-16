#!/usr/bin/env bash
#
# mayhem/test.sh — RUN nodogsplash's own tests/ suites plus a known-answer probe (all built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


B="$SRC/mayhem/build"
passed=0; failed=0

# The upstream suites are assert()-based: each prints "Starting test <name>" before a test and
# "Finished all tests." at the end, and an assert aborts. Count the started tests, and require the
# end marker, so an exit(0) stub can neither pass nor skip tests.
run_suite() { # <label> <dir> <binary> <expected number of tests>
  local label=$1 dir=$2 bin=$3 want=$4 out rc started
  [ -x "$SRC/$dir/$bin" ] || { echo "FAIL $label: $dir/$bin missing (build.sh bug)"; failed=$((failed+1)); return; }
  out=$(cd "$SRC/$dir" && ./"$bin" 2>&1); rc=$?
  started=$(printf '%s\n' "$out" | grep -c '^Starting test ')
  if [ "$rc" -eq 0 ] && [ "$started" -eq "$want" ] && printf '%s\n' "$out" | grep -q '^Finished all tests\.'; then
    echo "PASS $label ($started tests)"; passed=$((passed+started))
  else
    echo "FAIL $label: rc=$rc started=$started want=$want"; printf '%s\n' "$out" | tail -5
    failed=$((failed+1))
  fi
}
run_suite conf tests/conf test_conf 2
run_suite state_file tests/state_file test_state_file 14

# Known-answer probe: the templater and URL/base64 helpers compared to exact expected output.
expected='tmpl=a Bob,unknown;ver_x 5!
tmpl_trunc=a Bob,un
urlencode=36:http%3a%2f%2fa%20b%2fc%3fx%3d~%c3%a9
urlencode_overflow=-1
urldecode=5:a b/c
urldecode_bad=-2
b64decode=7:Hello!'
if [ -x "$B/kat" ]; then
  got=$("$B/kat" 2>&1)
  if [ "$got" = "$expected" ]; then
    echo "PASS kat (7 checks)"; passed=$((passed+7))
  else
    echo "FAIL kat"; diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got") || true
    failed=$((failed+1))
  fi
else
  echo "FAIL kat: $B/kat missing (build.sh bug)"; failed=$((failed+1))
fi

emit_ctrf "nodogsplash-assert+kat" "$passed" "$failed" 0
