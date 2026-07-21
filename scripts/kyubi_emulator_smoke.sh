#!/usr/bin/env bash
#####################################################################
#   Kyubi emulator install-and-launch smoke test
#####################################################################
#
# Runs inside a booted stock x86_64 AVD (via reactivecircus/android-emulator-
# runner). Confirms the Kyubi manager APK installs, launches, and does not crash
# on a clean device. It does NOT root the emulator -- Kyubi's offline system-mode
# install is BlueStacks-VHD-specific and can't run on a stock AVD; that is
# validated on real instances. This gate catches a broken/uninstallable/insta-
# crashing APK before it ships.
#
# Usage (as the android-emulator-runner `script:`): ./scripts/kyubi_emulator_smoke.sh
#####################################################################
set -euo pipefail

APK="out/app-release.apk"
PKG="io.github.robthepcguy.kyubi"

[ -f "$APK" ] || { echo "EMU SMOKE FAIL: $APK not found" >&2; exit 1; }

adb wait-for-device
# Clear the crash buffer so we only see crashes from THIS launch.
adb logcat -b crash -c || true

echo "* Installing $APK"
adb install -r -g "$APK"

echo "* Confirming install"
adb shell pm path "$PKG" >/dev/null || { echo "EMU SMOKE FAIL: $PKG not installed"; exit 1; }

echo "* Launching $PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
sleep 8

echo "* Checking the process survived launch"
if ! adb shell pidof "$PKG" >/dev/null 2>&1; then
  echo "EMU SMOKE FAIL: $PKG is not running 8s after launch (crashed or exited)"
  adb logcat -b crash -d || true
  exit 1
fi

echo "* Scanning the crash buffer"
crash="$(adb logcat -b crash -d || true)"
if echo "$crash" | grep -q "$PKG"; then
  echo "EMU SMOKE FAIL: $PKG appears in the crash buffer"
  echo "$crash"
  exit 1
fi

echo "EMU SMOKE OK: $PKG installed and launched cleanly."
