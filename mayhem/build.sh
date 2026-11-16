#!/usr/bin/env bash
#
# mayhem/build.sh — build nodogsplash's fuzz targets, standalone reproducers and the test suite.
# Runs in the commit image as `mayhem` in /mayhem; the base image exports the build contract
# (CC, SANITIZER_FLAGS, LIB_FUZZING_ENGINE, STANDALONE_FUZZ_MAIN, SRC). Fully offline: the only
# dependency (libjansson) is an apt -dev package installed in the Dockerfile.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) so an explicit empty SANITIZER_FLAGS builds without sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"

cd "$SRC"
B="$SRC/mayhem/build"            # gitignored (mayhem/.gitignore)
rm -rf "$B"
mkdir -p "$B/san" "$B/afl"

# Sources the targets need. state_file.c drags in the client list, the iptables layer and util.c.
CONF_SRCS="conf debug safe"
STATE_SRCS="client_list conf debug fw_abstract fw_common fw_iptables safe state_file tc util"
TMPL_SRCS="template"
ALL_SRCS=$(printf '%s\n' $CONF_SRCS $STATE_SRCS $TMPL_SRCS | sort -u)
CFLAGS_COMMON="-O1 -pthread -I$SRC/src -DWITH_STATE_FILE"

# 1) The project, instrumented. libFuzzer objects carry SanCov (fuzzer-no-link) unconditionally,
#    also when SANITIZER_FLAGS is empty; AFL objects get their instrumentation from afl-clang-fast.
for s in $ALL_SRCS; do
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $CFLAGS_COMMON \
      -c "src/$s.c" -o "$B/san/$s.o" &
  afl-clang-fast $SANITIZER_FLAGS $DEBUG_FLAGS $CFLAGS_COMMON \
      -c "src/$s.c" -o "$B/afl/$s.o" &
  while [ "$(jobs -rp | wc -l)" -ge "$MAYHEM_JOBS" ]; do wait -n; done
done
wait

# Leak sanitizer off at build time (leaks are not the bug class we fuzz for).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$B/lsan_off.o"

objs() { local d=$1; shift; local o=""; for s in "$@"; do o="$o $B/$d/$s.o"; done; echo "$o"; }
LIBS="-ljansson -lm -pthread"

# 2) libFuzzer targets, each linked twice: fuzzer engine, and the run-once standalone reproducer.
link_fuzzer() { # <name> <srcs...>
  local name=$1; shift
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $CFLAGS_COMMON $LIB_FUZZING_ENGINE \
      "mayhem/$name.c" $(objs san "$@") "$B/lsan_off.o" $LIBS -o "$SRC/$name"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link $CFLAGS_COMMON \
      "$STANDALONE_FUZZ_MAIN" "mayhem/$name.c" $(objs san "$@") "$B/lsan_off.o" $LIBS \
      -o "$SRC/$name-standalone"
}
link_fuzzer fuzz_template $TMPL_SRCS
link_fuzzer fuzz_state_file $STATE_SRCS

# 3) AFL file-input target (config_read() exit()s on every bad directive: one process per input).
afl-clang-fast $SANITIZER_FLAGS $DEBUG_FLAGS $CFLAGS_COMMON \
    mayhem/fuzz_conf.c $(objs afl $CONF_SRCS) "$B/lsan_off.o" $LIBS -o "$SRC/fuzz_conf"

# 4) Test suite with the project's NORMAL flags, independent of the sanitized build above:
#    upstream's own tests/ plus a known-answer probe for the templater and URL helpers.
(
  unset CFLAGS LDFLAGS
  export CFLAGS="-O2 -g -Wall $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
  make -C tests/conf test_conf
  make -C tests/state_file test_state_file
  $CC -O2 $COVERAGE_FLAGS -I"$SRC/src" mayhem/kat/kat.c src/template.c src/http_microhttpd_utils.c \
      -o "$B/kat"
)
