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

# Kyubi is not a recovery-flashable zip and ships no boot-image OTA survival:
# the META-INF updater and addon.d.sh (both carry boot-image logic) must be gone.
[[ "$listing" == *"META-INF/com/google/android/update-binary"* ]] && fail "flashable-zip updater embedded (update-binary) -- Kyubi is not recovery-flashable"
[[ "$listing" == *"META-INF/com/google/android/updater-script"* ]] && fail "flashable-zip updater-script embedded"
[[ "$listing" == *"assets/addon.d.sh"* ]] && fail "addon.d.sh shipped -- boot-image OTA survival must be removed"

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

# --- Version invariants -----------------------------------------------------
# The APK versionCode is a monotonic build code, NOT the Magisk core compat
# code. Ten releases shipped versionCode=31000, so anything <= 31000 is a
# downgrade Android will refuse to install over them.
if [ -n "$aapt" ]; then
  vc="$(echo "$badging" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)"
  [ -n "$vc" ] || fail "could not read versionCode from badging"
  [ "$vc" -gt 31000 ] || fail "versionCode $vc <= 31000 -- downgrade vs published releases"
  echo "  versionCode OK: $vc (> 31000)"
else
  echo "  WARN: aapt not found -- skipping versionCode assertion"
fi

# The APK comment must name both numbers explicitly. setupAppCommon() is shared
# with the stub (whose manifest versionCode is 1), so a bare `versionCode=` key
# would be ambiguous when read off a stub APK.
comment="$(unzip -z "$APK" 2>/dev/null || true)"
[[ "$comment" == *"buildCode="*             ]] || fail "APK comment missing buildCode="
[[ "$comment" == *"coreVersionCode=31000"*  ]] || fail "APK comment missing coreVersionCode=31000"
# Must match the BARE key only. `coreVersionCode=` contains `versionCode=` as a
# substring, so anchor the test to a line start.
[[ "$comment" == *$'\n'"versionCode="*      ]] && fail "APK comment uses ambiguous versionCode= key"

# The comment is what CI reads to build the feed; the manifest is what Android
# reads to decide upgrades. If plumbing ever drifts they disagree silently and
# the feed advertises a build code no installed APK actually carries.
if [ -n "$aapt" ]; then
  cbc="$(echo "$comment" | sed -n 's/^buildCode=\([0-9]*\)$/\1/p')"
  [ -n "$cbc" ] || fail "could not parse buildCode from APK comment"
  [ "$cbc" -eq "$vc" ] || fail "APK comment buildCode $cbc != manifest versionCode $vc"
  echo "  APK comment OK: buildCode $cbc matches manifest versionCode"
else
  echo "  APK comment OK: buildCode + coreVersionCode present (no aapt to cross-check)"
fi

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

# The feed base must carry the /Kyubi/ project-pages segment. Without it,
# stable.json resolves against the USER pages site, not this repo's.
const_kt="app/src/main/java/com/topjohnwu/magisk/core/Const.kt"
base="$(sed -n 's/.*GITHUB_PAGE_URL = "\([^"]*\)".*/\1/p' "$const_kt")"
[ "$base" = "https://robthepcguy.github.io/Kyubi/" ] \
  || fail "feed base URL is '$base', expected https://robthepcguy.github.io/Kyubi/"
echo "  feed base URL OK: $base"

echo "SMOKE OK."
