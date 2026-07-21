#!/usr/bin/env bash
#####################################################################
#   Kyubi build-invariant smoke test
#####################################################################
#
# Asserts, on a built release APK, the reductions that DEFINE Kyubi -- so CI
# fails the moment a change quietly reintroduces ARM, drags magiskboot back in,
# breaks the package rename, or repoints an update feed at upstream. This does
# NOT test the offline system-mode root install: that is BlueStacks-VHD-specific
# and can't be reproduced on a stock AVD (see kyubi_emulator_smoke.sh for the
# install-and-launch check that CAN run in CI).
#
# Usage: ./scripts/kyubi_smoke.sh out/app-release.apk
#
# Note: matches are done with bash string tests, not `... | grep -q`. Under
# `set -o pipefail`, grep -q exiting early on a match sends SIGPIPE to the
# writer, whose 141 exit then fails the pipeline -- a false negative. Pure-bash
# `[[ $var == *needle* ]]` has no such trap.
#####################################################################
set -euo pipefail

APK="${1:?usage: kyubi_smoke.sh <apk>}"
PKG="io.github.robthepcguy.kyubi"

[ -f "$APK" ] || { echo "SMOKE FAIL: APK not found: $APK" >&2; exit 1; }
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

# --- APK shape --------------------------------------------------------------
unzip -l "$APK" >/dev/null 2>&1 || fail "$APK is not a valid APK/zip"
listing="$(unzip -l "$APK")"

[[ "$listing" == *"lib/x86/"*      ]] || fail "missing lib/x86/ (x86 ABI)"
[[ "$listing" == *"lib/x86_64/"*   ]] || fail "missing lib/x86_64/ (x86_64 ABI)"
[[ "$listing" == *"lib/armeabi"*   ]] && fail "armeabi ABI present -- Kyubi is x86-only"
[[ "$listing" == *"lib/arm64"*     ]] && fail "arm64 ABI present -- Kyubi is x86-only"
[[ "${listing,,}" == *"magiskboot"* ]] && fail "magiskboot present -- must be stripped (system-mode only)"

# package id (aapt if the runner has build-tools; otherwise skip with a warning)
aapt=""
for c in "${ANDROID_HOME:-}"/build-tools/*/aapt "${ANDROID_SDK_ROOT:-}"/build-tools/*/aapt; do
  [ -x "$c" ] && aapt="$c"
done
if [ -n "$aapt" ]; then
  badging="$("$aapt" dump badging "$APK" 2>/dev/null || true)"
  [[ "$badging" == *"package: name='$PKG'"* ]] || fail "package id is not $PKG"
  echo "  package id OK: $PKG"
else
  echo "  WARN: aapt not found -- skipping package-id assertion"
fi
echo "APK shape OK: x86-only, magiskboot-free."

# --- Feed / URL regression guard -------------------------------------------
# The compiled-in update feeds and source URLs must point at Kyubi, never back
# at upstream Kitsune/Magisk. Scoped to the feed sources only -- upstream author
# CREDIT links in DeveloperItem.kt are legitimate and intentionally untouched.
feed_sources="app/src/main/java/com/topjohnwu/magisk/core/Const.kt stub/src/main/java"
guard() {
  if grep -RInE "$1" $feed_sources 2>/dev/null; then
    fail "upstream feed/URL '$1' leaked back into a Kyubi feed source"
  fi
}
guard '1q23lyc45'
guard 'huskydg\.github\.io'
guard 'topjohnwu/magisk-files'
guard 'KitsuneMagisk/releases'
echo "Feed/URL guard OK: no upstream feeds."

echo "SMOKE OK."
