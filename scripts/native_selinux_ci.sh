#!/usr/bin/env bash
# Disposable CI AVD only. Exercise the same APK binary with SELinux enabled.
set -euo pipefail
serial="$(timeout 15 adb get-serialno)"
timeout 15 adb root
timeout 30 adb wait-for-device
unzip -p out/app-debug.apk lib/x86_64/libmagisk64.so > /tmp/kyubi-native-magisk64
timeout 15 adb push /tmp/kyubi-native-magisk64 /data/local/tmp/kyubi-native-magisk64
timeout 15 adb shell chmod 755 /data/local/tmp/kyubi-native-magisk64
trap 'timeout 15 adb shell rm -f /data/local/tmp/kyubi-native-magisk64' EXIT
# Keep SELinux enabled while allowing the test's arbitrary ownership fixtures.
# Permissive must still preserve labels, unlike a disabled kernel.
timeout 15 adb shell setenforce 0
test "$(timeout 15 adb shell getenforce | tr -d '\r')" = Permissive
python3 scripts/test_native_selinux.py --serial "$serial" --binary /data/local/tmp/kyubi-native-magisk64
timeout 15 adb shell setenforce 1
